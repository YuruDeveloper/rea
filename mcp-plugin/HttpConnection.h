#ifndef HTTPCONNECTION_H
#define HTTPCONNECTION_H

#include "HttpRequest.h"
#include "HttpRequestParser.h"

#include <QList>
#include <QObject>
#include <QPair>

class QTcpSocket;
class QTimer;

class HttpConnection : public QObject
{
    Q_OBJECT

public:
    using HeaderList = QList<QPair<QByteArray, QByteArray>>;

    explicit HttpConnection(QTcpSocket *socket, QObject *parent = nullptr);

    void sendResponse(int status, const HeaderList &headers, const QByteArray &body);

signals:
    void requestReady(const HttpRequest &request);

private slots:
    void readAvailable();

private:
    QTcpSocket *socket;
    QTimer *receiveTimer;
    HttpRequestParser parser;
    bool responded = false;
};

#endif // HTTPCONNECTION_H
