#include "McpPlugin.h"

#include "McpServer.h"

#include <QDebug>

void McpPlugin::setupPlugin()
{
    server = new McpServer(this);
    QString errorMessage;
    if (!server->start(&errorMessage)) {
        qWarning() << "The MCP server did not start:" << errorMessage;
    }
}

void McpPlugin::setupInterface(MainWindow *) {}

void McpPlugin::terminate()
{
    if (server) {
        server->stop();
    }
}
