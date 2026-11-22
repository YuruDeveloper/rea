#ifndef HTTPREQUESTPARSER_H
#define HTTPREQUESTPARSER_H

#include "HttpRequest.h"

#include <QByteArray>

class HttpRequestParser
{
public:
    enum class Status { NeedsMoreData, Ready, Failed };

    static constexpr qsizetype MaxHeadBytes = 16 * 1024;
    static constexpr qsizetype MaxBodyBytes = 1024 * 1024;

    Status feed(const QByteArray &data);
    Status status() const { return currentStatus; }
    const HttpRequest &request() const { return parsedRequest; }
    int failureStatus() const { return httpFailureStatus; }
    bool takeContinueRequest();

private:
    Status fail(int httpStatus);
    bool readHead();
    int parseHead(const QByteArray &head);

    Status currentStatus = Status::NeedsMoreData;
    bool headIsComplete = false;
    bool continueIsRequested = false;
    int httpFailureStatus = 0;
    QByteArray buffer;
    HttpRequest parsedRequest;
    qsizetype contentLength = 0;
};

#endif // HTTPREQUESTPARSER_H
