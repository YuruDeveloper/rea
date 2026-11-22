#ifndef TOOLCATALOG_H
#define TOOLCATALOG_H

#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QStringList>

class ToolCatalog
{
public:
    static const QString ListFunctions;
    static const QString DecompileFunction;

    static const int DefaultListLimit = 200;
    static const int MaxListLimit = 1000;

    static QJsonArray definitions();
    static bool contains(const QString &name);
    static QStringList unknownArguments(const QString &name, const QJsonObject &arguments);

private:
    static QJsonObject readOnlyTool(const QString &name, const QString &title,
                                    const QString &description, const QJsonObject &inputSchema);
};

#endif // TOOLCATALOG_H
