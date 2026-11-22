#ifndef TOOLWORKER_H
#define TOOLWORKER_H

#include <QJsonObject>
#include <QMap>
#include <QObject>
#include <QString>

#include <rz_core.h>

class ToolWorker : public QObject
{
    Q_OBJECT

public slots:
    void runTool(quint64 callId, const QString &name, const QJsonObject &arguments);

signals:
    void toolFinished(quint64 callId, const QJsonObject &result);

private:
    static QJsonObject callTool(const QString &name, const QJsonObject &arguments);
    static QJsonObject listFunctions(const QJsonObject &arguments);
    static QMap<quint64, QJsonObject> collectFunctions(const QString &filter);
    static QJsonObject decompileFunction(const QJsonObject &arguments);
    static QJsonObject disassembleFunction(const QJsonObject &arguments);
    static QJsonObject findReferences(const QJsonObject &arguments);
    static QJsonObject listStrings(const QJsonObject &arguments);
    static QJsonObject listImports(const QJsonObject &arguments);
    static QJsonObject getCurrentLocation();
    static RzAnalysisFunction *findFunction(RzCore *core, const QJsonObject &arguments,
                                            QString *errorMessage);
};

#endif // TOOLWORKER_H
