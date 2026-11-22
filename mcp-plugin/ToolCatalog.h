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
    static const QString DisassembleFunction;
    static const QString FindReferences;
    static const QString ListStrings;
    static const QString ListImports;
    static const QString GetCurrentLocation;

    static const int DefaultListLimit = 200;
    static const int MaxListLimit = 1000;

    static QJsonArray definitions();
    static bool contains(const QString &name);
    static QStringList unknownArguments(const QString &name, const QJsonObject &arguments);

private:
    static QJsonObject readOnlyTool(const QString &name, const QString &title,
                                    const QString &description, const QJsonObject &inputSchema);
    static QJsonObject listSchema(const QString &filterDescription);
    static QJsonObject functionSchema();
    static QJsonObject referenceSchema();
    static QJsonObject emptySchema();
};

#endif // TOOLCATALOG_H
