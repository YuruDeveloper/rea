#ifndef MCPOUTCOME_H
#define MCPOUTCOME_H

#include <QJsonObject>
#include <QJsonValue>
#include <QString>

struct McpOutcome
{
    enum class Kind { Reply, Accepted, ToolCall };

    Kind kind = Kind::Accepted;
    int httpStatus = 202;
    QJsonObject reply;
    QJsonValue requestId;
    QString toolName;
    QJsonObject toolArguments;
};

#endif // MCPOUTCOME_H
