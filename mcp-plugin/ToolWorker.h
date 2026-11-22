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
    static QJsonObject listFunctions(const QJsonObject &arguments);
    static QMap<quint64, QJsonObject> collectFunctions(const QString &filter);
    static QJsonObject decompileFunction(const QJsonObject &arguments);
    static RzAnalysisFunction *findFunction(RzCore *core, const QString &target,
                                            QString *errorMessage);
    static bool readInteger(const QJsonObject &arguments, const QString &name, qint64 minimum,
                            qint64 maximum, qint64 *value);
    static QString formatAddress(quint64 address);
    static QJsonObject makeDataResult(const QJsonObject &data);
    static QJsonObject makeErrorResult(const QString &message);
    static QJsonObject makeTextResult(const QString &text, bool isError);
};

#endif // TOOLWORKER_H
