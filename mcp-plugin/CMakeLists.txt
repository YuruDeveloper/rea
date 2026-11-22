cmake_minimum_required(VERSION 3.16)
project(rea-mcp-plugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Cutter REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Network)

# The default of the Cutter package is a folder in the user profile.
# This default keeps the plugin below the install prefix.
set(CUTTER_INSTALL_PLUGDIR "plugins/native" CACHE STRING
    "Directory to install the Cutter plugin into, relative to the install prefix")

set(CMAKE_AUTOMOC ON)

add_library(mcp_cutter MODULE
    HttpConnection.cpp
    HttpConnection.h
    HttpRequest.h
    HttpRequestParser.cpp
    HttpRequestParser.h
    McpMessageHandler.cpp
    McpMessageHandler.h
    McpOutcome.h
    McpPlugin.cpp
    McpPlugin.h
    McpServer.cpp
    McpServer.h
    ToolArguments.cpp
    ToolArguments.h
    ToolCatalog.cpp
    ToolCatalog.h
    ToolResult.cpp
    ToolResult.h
    ToolWorker.cpp
    ToolWorker.h)
target_link_libraries(mcp_cutter PRIVATE Cutter::Cutter Qt6::Network)
install(TARGETS mcp_cutter DESTINATION "${CUTTER_INSTALL_PLUGDIR}")
