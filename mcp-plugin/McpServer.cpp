#include "McpServer.h"

#include "HttpConnection.h"
#include "McpMessageHandler.h"
#include "ToolWorker.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>

namespace {

const QByteArray EndpointPath = "/mcp";
const QByteArray BearerPrefix = "bearer ";
const char *const DirectoryVariable = "REA_MCP_DIR";
const int TokenWords = 8;

bool constantTimeEquals(const QByteArray &left, const QByteArray &right)
{
    if (left.size() != right.size()) {
        return false;
    }
    unsigned char difference = 0;
    for (qsizetype i = 0; i < left.size(); i++) {
        difference |= static_cast<unsigned char>(left[i] ^ right[i]);
    }
    return difference == 0;
}

}

McpServer::McpServer(QObject *parent) : QObject(parent), tcpServer(new QTcpServer(this))
{
    auto *worker = new ToolWorker();
    worker->moveToThread(&workerThread);
    connect(&workerThread, &QThread::finished, worker, &QObject::deleteLater);
    connect(this, &McpServer::toolRequested, worker, &ToolWorker::runTool);
    connect(worker, &ToolWorker::toolFinished, this, &McpServer::finishToolCall);
    connect(tcpServer, &QTcpServer::newConnection, this, &McpServer::acceptConnections);
}

McpServer::~McpServer()
{
    stop();
}

bool McpServer::start(QString *errorMessage)
{
    QList<quint32> words(TokenWords);
    QRandomGenerator::system()->fillRange(words.data(), words.size());
    token = QByteArray(reinterpret_cast<const char *>(words.constData()),
                       words.size() * static_cast<qsizetype>(sizeof(quint32)))
                    .toHex();

    if (!tcpServer->listen(QHostAddress::LocalHost, 0)) {
        *errorMessage = tcpServer->errorString();
        return false;
    }
    if (!writeConnectionFile(errorMessage)) {
        tcpServer->close();
        return false;
    }
    workerThread.start();
    qInfo() << "The MCP server listens on port" << tcpServer->serverPort()
            << "and the connection file is" << connectionFilePath;
    return true;
}

void McpServer::stop()
{
    tcpServer->close();
    if (!connectionFilePath.isEmpty()) {
        QFile::remove(connectionFilePath);
        connectionFilePath.clear();
    }
    workerThread.quit();
    workerThread.wait();
}

void McpServer::acceptConnections()
{
    while (QTcpSocket *socket = tcpServer->nextPendingConnection()) {
        auto *connection = new HttpConnection(socket, this);
        connect(connection, &HttpConnection::requestReady, this,
                [this, connection](const HttpRequest &request) {
                    handleRequest(connection, request);
                });
    }
}

void McpServer::finishToolCall(quint64 callId, const QJsonObject &result)
{
    const PendingCall call = pendingCalls.take(callId);
    if (!call.connection) {
        return;
    }
    sendJson(call.connection, 200, McpMessageHandler::makeResult(call.requestId, result));
}

void McpServer::handleRequest(HttpConnection *connection, const HttpRequest &request)
{
    const HttpConnection::HeaderList challengeHeaders { { "WWW-Authenticate", "Bearer" } };
    const HttpConnection::HeaderList allowHeaders { { "Allow", "POST" } };
    if (request.lowerCaseHeaders.contains("origin")) {
        sendRefusal(connection, 403, "A request with an Origin header is not accepted");
        return;
    }
    if (!isAuthorized(request)) {
        connection->sendResponse(401, challengeHeaders, {});
        return;
    }
    if (request.target != EndpointPath) {
        sendRefusal(connection, 404, "The endpoint is " + EndpointPath);
        return;
    }
    if (request.method != "POST") {
        connection->sendResponse(405, allowHeaders, {});
        return;
    }
    const QByteArray version = request.lowerCaseHeaders.value("mcp-protocol-version");
    if (!version.isEmpty() && !McpMessageHandler::isSupportedVersion(version)) {
        sendRefusal(connection, 400, "This protocol version is not supported: " + version);
        return;
    }

    const McpOutcome outcome = McpMessageHandler::handle(request.body);
    if (outcome.kind == McpOutcome::Kind::Accepted) {
        connection->sendResponse(202, {}, {});
        return;
    }
    if (outcome.kind == McpOutcome::Kind::Reply) {
        sendJson(connection, outcome.httpStatus, outcome.reply);
        return;
    }
    const quint64 callId = nextCallId++;
    pendingCalls.insert(callId, PendingCall { connection, outcome.requestId });
    emit toolRequested(callId, outcome.toolName, outcome.toolArguments);
}

bool McpServer::isAuthorized(const HttpRequest &request) const
{
    const QByteArray authorization = request.lowerCaseHeaders.value("authorization");
    if (authorization.left(BearerPrefix.size()).toLower() != BearerPrefix) {
        return false;
    }
    return constantTimeEquals(authorization.mid(BearerPrefix.size()), token);
}

bool McpServer::writeConnectionFile(QString *errorMessage)
{
    const QDir directory(connectionDirectory());
    if (!directory.mkpath(".")) {
        *errorMessage = "Could not create the folder " + directory.absolutePath();
        return false;
    }
    const qint64 processId = QCoreApplication::applicationPid();
    QJsonObject content;
    content.insert("url",
                   QString("http://127.0.0.1:%1%2")
                           .arg(tcpServer->serverPort())
                           .arg(QString::fromLatin1(EndpointPath)));
    content.insert("token", QString::fromLatin1(token));
    content.insert("pid", processId);
    content.insert("startedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    QFile file(directory.filePath(QString("server-%1.json").arg(processId)));
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        *errorMessage = "Could not write the file " + file.fileName();
        return false;
    }
    file.write(QJsonDocument(content).toJson(QJsonDocument::Indented));
    connectionFilePath = file.fileName();
    return true;
}

QString McpServer::connectionDirectory()
{
    const QString fromEnvironment = qEnvironmentVariable(DirectoryVariable);
    if (!fromEnvironment.isEmpty()) {
        return fromEnvironment;
    }
    return QDir(QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation))
            .filePath("mcp");
}

void McpServer::sendJson(HttpConnection *connection, int status, const QJsonObject &body)
{
    connection->sendResponse(status, { { "Content-Type", "application/json" } },
                             QJsonDocument(body).toJson(QJsonDocument::Compact));
}

void McpServer::sendRefusal(HttpConnection *connection, int status, const QString &message)
{
    QJsonObject body;
    body.insert("error", message);
    sendJson(connection, status, body);
}
