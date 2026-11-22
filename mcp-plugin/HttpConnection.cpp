#include "HttpConnection.h"

#include <QTcpSocket>
#include <QTimer>

namespace {

const int ReceiveTimeoutMilliseconds = 30 * 1000;

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
    if (responded || parser.status() != HttpRequestParser::Status::NeedsMoreData) {
        socket->readAll();
        return;
    }
    const HttpRequestParser::Status status = parser.feed(socket->readAll());
    if (parser.takeContinueRequest()) {
        socket->write("HTTP/1.1 100 Continue\r\n\r\n");
    }
    if (status == HttpRequestParser::Status::Failed) {
        sendResponse(parser.failureStatus(), {}, {});
        return;
    }
    if (status == HttpRequestParser::Status::NeedsMoreData) {
        return;
    }
    receiveTimer->stop();
    emit requestReady(parser.request());
}
