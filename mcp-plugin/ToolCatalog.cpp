#include "ToolCatalog.h"

#include <QJsonObject>

const QString ToolCatalog::ListFunctions = QStringLiteral("list_functions");
const QString ToolCatalog::DecompileFunction = QStringLiteral("decompile_function");

QJsonArray ToolCatalog::definitions()
{
    const QJsonObject filterProperty {
        { "type", "string" },
        { "description",
          "Keep only the functions whose name contains this text. The comparison "
          "ignores case." }
    };
    const QJsonObject offsetProperty { { "type", "integer" },
                                       { "minimum", 0 },
                                       { "default", 0 },
                                       { "description",
                                         "Number of functions to skip, after the filter." } };
    const QJsonObject limitProperty { { "type", "integer" },
                                      { "minimum", 1 },
                                      { "maximum", MaxListLimit },
                                      { "default", DefaultListLimit },
                                      { "description", "Maximum number of functions to return." } };
    const QJsonObject listProperties { { "filter", filterProperty },
                                       { "offset", offsetProperty },
                                       { "limit", limitProperty } };
    const QJsonObject listSchema { { "type", "object" },
                                   { "properties", listProperties },
                                   { "additionalProperties", false } };

    const QJsonObject functionProperty {
        { "type", "string" },
        { "description",
          "A function name from list_functions, or an address in the function. "
          "Write an address as hexadecimal with the 0x prefix, or as decimal." }
    };
    const QJsonObject decompileProperties { { "function", functionProperty } };
    const QJsonArray decompileRequired { "function" };
    const QJsonObject decompileSchema { { "type", "object" },
                                        { "properties", decompileProperties },
                                        { "required", decompileRequired },
                                        { "additionalProperties", false } };

    return QJsonArray {
        readOnlyTool(ListFunctions, "List functions",
                     "Lists the functions that the analysis found in the binary that is open in "
                     "the session. Returns the address, the name and the size of each function, "
                     "in the order of the addresses. Use filter, offset and limit when the binary "
                     "has many functions.",
                     listSchema),
        readOnlyTool(DecompileFunction, "Decompile a function",
                     "Decompiles one function of the binary that is open in the session and "
                     "returns C-like pseudocode. The decompiler is rz-ghidra.",
                     decompileSchema)
    };
}

bool ToolCatalog::contains(const QString &name)
{
    return name == ListFunctions || name == DecompileFunction;
}

QStringList ToolCatalog::unknownArguments(const QString &name, const QJsonObject &arguments)
{
    QJsonObject properties;
    const QJsonArray tools = definitions();
    for (const QJsonValue &tool : tools) {
        if (tool.toObject().value("name").toString() == name) {
            properties =
                    tool.toObject().value("inputSchema").toObject().value("properties").toObject();
        }
    }
    QStringList unknownKeys;
    const QStringList keys = arguments.keys();
    for (const QString &key : keys) {
        if (!properties.contains(key)) {
            unknownKeys.append(key);
        }
    }
    return unknownKeys;
}

QJsonObject ToolCatalog::readOnlyTool(const QString &name, const QString &title,
                                      const QString &description, const QJsonObject &inputSchema)
{
    const QJsonObject annotations { { "title", title },
                                    { "readOnlyHint", true },
                                    { "openWorldHint", false } };
    return QJsonObject { { "name", name },
                         { "title", title },
                         { "description", description },
                         { "inputSchema", inputSchema },
                         { "annotations", annotations } };
}
