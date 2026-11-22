#ifndef TOOLARGUMENTS_H
#define TOOLARGUMENTS_H

#include <QJsonObject>
#include <QString>

class ToolArguments
{
public:
    static bool parseAddress(const QString &text, quint64 *address);
    static bool readList(const QJsonObject &arguments, QString *filter, qint64 *offset,
                         qint64 *limit, QString *errorMessage);

private:
    static bool readInteger(const QJsonObject &arguments, const QString &name, qint64 minimum,
                            qint64 maximum, qint64 *value);
};

#endif // TOOLARGUMENTS_H
