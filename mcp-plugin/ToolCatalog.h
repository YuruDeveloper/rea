#ifndef TOOLCATALOG_H
#define TOOLCATALOG_H

#include <QJsonArray>
#include <QString>

class ToolCatalog
{
public:
    static const QString ListFunctions;
    static const QString DecompileFunction;

    static const int DefaultListLimit = 200;
    static const int MaxListLimit = 1000;

    static QJsonArray definitions();
    static bool contains(const QString &name);

private:
    static QJsonObject readOnlyTool(const QString &name, const QString &title,
                                    const QString &description, const QJsonObject &inputSchema);
};

#endif // TOOLCATALOG_H
