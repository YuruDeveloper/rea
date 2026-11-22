#include "HttpRequestParser.h"

#include <QList>

namespace {

const int HeadIsValid = 0;

}

HttpRequestParser::Status HttpRequestParser::feed(const QByteArray &data)
{
    if (currentStatus != Status::NeedsMoreData) {
        return currentStatus;
    }
    buffer.append(data);

    if (!headIsComplete && !readHead()) {
        return currentStatus;
    }
    if (buffer.size() < contentLength) {
        return currentStatus;
    }
    parsedRequest.body = buffer.left(contentLength);
    buffer.clear();
    currentStatus = Status::Ready;
    return currentStatus;
}

bool HttpRequestParser::takeContinueRequest()
{
    const bool wasRequested = continueIsRequested;
    continueIsRequested = false;
    return wasRequested;
}

HttpRequestParser::Status HttpRequestParser::fail(int httpStatus)
{
    httpFailureStatus = httpStatus;
    buffer.clear();
    currentStatus = Status::Failed;
    return currentStatus;
}

bool HttpRequestParser::readHead()
{
    const qsizetype headEnd = buffer.indexOf("\r\n\r\n");
    if (headEnd < 0 && buffer.size() <= MaxHeadBytes) {
        return false;
    }
    if (headEnd < 0 || headEnd > MaxHeadBytes) {
        fail(431);
        return false;
    }
    const int headStatus = parseHead(buffer.left(headEnd));
    if (headStatus != HeadIsValid) {
        fail(headStatus);
        return false;
    }
    buffer.remove(0, headEnd + 4);
    headIsComplete = true;
    continueIsRequested =
            parsedRequest.lowerCaseHeaders.value("expect").toLower() == "100-continue";
    return true;
}

int HttpRequestParser::parseHead(const QByteArray &head)
{
    const QList<QByteArray> lines = head.split('\n');
    const QList<QByteArray> requestLine = lines.first().trimmed().split(' ');
    if (requestLine.size() != 3 || !requestLine[2].startsWith("HTTP/1.")) {
        return 400;
    }
    parsedRequest.method = requestLine[0];
    parsedRequest.target = requestLine[1];

    for (qsizetype i = 1; i < lines.size(); i++) {
        const QByteArray line = lines[i].trimmed();
        const qsizetype colon = line.indexOf(':');
        if (colon <= 0) {
            return 400;
        }
        parsedRequest.lowerCaseHeaders.insert(line.left(colon).trimmed().toLower(),
                                              line.mid(colon + 1).trimmed());
    }

    if (parsedRequest.lowerCaseHeaders.contains("transfer-encoding")) {
        return 501;
    }
    if (!parsedRequest.lowerCaseHeaders.contains("content-length")) {
        return parsedRequest.method == "POST" ? 411 : HeadIsValid;
    }
    bool isNumber = false;
    const qlonglong length =
            parsedRequest.lowerCaseHeaders.value("content-length").toLongLong(&isNumber);
    if (!isNumber || length < 0) {
        return 400;
    }
    if (length > MaxBodyBytes) {
        return 413;
    }
    contentLength = length;
    return HeadIsValid;
}
