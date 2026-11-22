#ifndef MCPPLUGIN_H
#define MCPPLUGIN_H

#include <QObject>

#include <CutterPlugin.h>

class McpServer;

class McpPlugin : public QObject, CutterPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "re.rizin.cutter.plugins.CutterPlugin")
    Q_INTERFACES(CutterPlugin)

public:
    void setupPlugin() override;
    void setupInterface(MainWindow *main) override;
    void terminate() override;

    QString getName() const override { return "MCP Server"; }
    QString getAuthor() const override { return "rea"; }
    QString getDescription() const override
    {
        return "Lets a local agent read the analysis session through the Model Context Protocol.";
    }
    QString getVersion() const override { return "0.1.0"; }

private:
    McpServer *server = nullptr;
};

#endif // MCPPLUGIN_H
