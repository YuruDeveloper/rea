#include "HttpConnection.h"

#include <QTcpSocket>
#include <QTimer>

namespace {

const qsizetype MaxHeadBytes = 16 * 1024;
const qsizetype MaxBodyBytes = 1024 * 1024;
const int ReceiveTimeoutMilliseconds = 30 * 1000;
const int HeadIsValid = 0;

QByteArray reasonPhrase(int status)
{
    switch (status) {
    case 200:
        return "OK";
    case 202:
        return "Accepted";
    case 400:
        return "Bad Request";
    case 401:
        return "Unauthorized";
    case 403:
        return "Forbidden";
    case 404:
        return "Not Found";
    case 405:
        return "Method Not Allowed";
    case 408:
        return "Request Timeout";
    case 411:
        return "Length Required";
    case 413:
        return "Content Too Large";
    case 431:
        return "Request Header Fields Too Large";
    case 501:
        return "Not Implemented";
    default:
        return "Error";
    }
}

}

HttpConnection::HttpConnection(QTcpSocket *socket, QObject *parent)
    : QObject(parent), socket(socket), receiveTimer(new QTimer(this))
{
    socket->setParent(this);
    receiveTimer->setSingleShot(true);
    connect(receiveTimer, &QTimer::timeout, this, [this]() { sendResponse(408, {}, {}); });
    connect(socket, &QTcpSocket::readyRead, this, &HttpConnection::readAvailable);
    connect(socket, &QTcpSocket::disconnected, this, &QObject::deleteLater);
    receiveTimer->start(ReceiveTimeoutMilliseconds);
}

void HttpConnection::sendResponse(int status, const HeaderList &headers, const QByteArray &body)
{
    if (responded) {
        return;
    }
    responded = true;
    state = State::Done;
    receiveTimer->stop();

    QByteArray response;
    response += "HTTP/1.1 " + QByteArray::number(status) + " " + reasonPhrase(status) + "\r\n";
    response += "Content-Length: " + QByteArray::number(body.size()) + "\r\n";
    response += "Connection: close\r\n";
    for (const auto &header : headers) {
        response += header.first + ": " + header.second + "\r\n";
    }
    response += "\r\n";
    response += body;
    socket->write(response);
    socket->disconnectFromHost();
}

void HttpConnection::readAvailable()
{
    if (state == State::Done) {
        socket->readAll();
        return;
    }
    buffer.append(socket->readAll());

    if (state == State::Head && !readHead()) {
        return;
    }
    if (buffer.size() < contentLength) {
        return;
    }
    request.body = buffer.left(contentLength);
    buffer.clear();
    state = State::Done;
    receiveTimer->stop();
    emit requestReady(request);
}

bool HttpConnection::readHead()
{
    const qsizetype headEnd = buffer.indexOf("\r\n\r\n");
    if (headEnd < 0 && buffer.size() <= MaxHeadBytes) {
        return false;
    }
    if (headEnd < 0 || headEnd > MaxHeadBytes) {
        sendResponse(431, {}, {});
        return false;
    }
    const int headStatus = parseHead(buffer.left(headEnd));
    if (headStatus != HeadIsValid) {
        sendResponse(headStatus, {}, {});
        return false;
    }
    buffer.remove(0, headEnd + 4);
    state = State::Body;
    if (request.lowerCaseHeaders.value("expect").toLower() == "100-continue") {
        socket->write("HTTP/1.1 100 Continue\r\n\r\n");
    }
    return true;
}

int HttpConnection::parseHead(const QByteArray &head)
{
    const QList<QByteArray> lines = head.split('\n');
    const QList<QByteArray> requestLine = lines.first().trimmed().split(' ');
    if (requestLine.size() != 3 || !requestLine[2].startsWith("HTTP/1.")) {
        return 400;
    }
    request.method = requestLine[0];
    request.target = requestLine[1];

    for (qsizetype i = 1; i < lines.size(); i++) {
        const QByteArray line = lines[i].trimmed();
        const qsizetype colon = line.indexOf(':');
        if (colon <= 0) {
            return 400;
        }
        request.lowerCaseHeaders.insert(line.left(colon).trimmed().toLower(),
                                        line.mid(colon + 1).trimmed());
    }

    if (request.lowerCaseHeaders.contains("transfer-encoding")) {
        return 501;
    }
    if (!request.lowerCaseHeaders.contains("content-length")) {
        return request.method == "POST" ? 411 : HeadIsValid;
    }
    bool isNumber = false;
    const qlonglong length = request.lowerCaseHeaders.value("content-length").toLongLong(&isNumber);
    if (!isNumber || length < 0) {
        return 400;
    }
    if (length > MaxBodyBytes) {
        return 413;
    }
    contentLength = length;
    return HeadIsValid;
}
