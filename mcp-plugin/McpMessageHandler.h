#ifndef MCPMESSAGEHANDLER_H
#define MCPMESSAGEHANDLER_H

#include "McpOutcome.h"

#include <QByteArray>

class McpMessageHandler
{
public:
    static McpOutcome handle(const QByteArray &body);
    static bool isSupportedVersion(const QString &version);
    static QJsonObject makeResult(const QJsonValue &requestId, const QJsonObject &result);
    static QJsonObject makeError(const QJsonValue &requestId, int code, const QString &message);

private:
    static McpOutcome reply(int httpStatus, const QJsonObject &message);
    static McpOutcome handleRequest(const QJsonValue &requestId, const QString &method,
                                    const QJsonObject &parameters);
    static McpOutcome handleToolCall(const QJsonValue &requestId, const QJsonObject &parameters);
    static QJsonObject initializeResult(const QJsonObject &parameters);
};

#endif // MCPMESSAGEHANDLER_H
