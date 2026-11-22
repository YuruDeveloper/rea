#ifndef TOOLRESULT_H
#define TOOLRESULT_H

#include <QJsonObject>
#include <QList>
#include <QString>

class ToolResult
{
public:
    static QJsonObject makeData(const QJsonObject &data);
    static QJsonObject makePage(const QList<QJsonObject> &matches, qint64 offset, qint64 limit,
                                const QString &listName);
    static QJsonObject makeError(const QString &message);
    static QString formatAddress(quint64 address);

private:
    static QJsonObject makeText(const QString &text, bool isError);
};

#endif // TOOLRESULT_H
