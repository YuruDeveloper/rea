#ifndef MCPSERVER_H
#define MCPSERVER_H

#include "HttpRequest.h"

#include <QHash>
#include <QJsonObject>
#include <QJsonValue>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QThread>

class HttpConnection;
class QTcpServer;

class McpServer : public QObject
{
    Q_OBJECT

public:
    explicit McpServer(QObject *parent = nullptr);
    ~McpServer() override;

    bool start(QString *errorMessage);
    void stop();

signals:
    void toolRequested(quint64 callId, const QString &name, const QJsonObject &arguments);

private slots:
    void acceptConnections();
    void finishToolCall(quint64 callId, const QJsonObject &result);

private:
    struct PendingCall
    {
        QPointer<HttpConnection> connection;
        QJsonValue requestId;
    };

    void handleRequest(HttpConnection *connection, const HttpRequest &request);
    bool isAuthorized(const HttpRequest &request) const;
    bool writeConnectionFile(QString *errorMessage);
    static QString connectionDirectory();
    static void sendJson(HttpConnection *connection, int status, const QJsonObject &body);
    static void sendRefusal(HttpConnection *connection, int status, const QString &message);

    QTcpServer *tcpServer;
    QThread workerThread;
    QByteArray token;
    QString connectionFilePath;
    QHash<quint64, PendingCall> pendingCalls;
    quint64 nextCallId = 1;
};

#endif // MCPSERVER_H
