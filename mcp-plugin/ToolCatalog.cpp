#include "ToolCatalog.h"

#include <QJsonObject>

const QString ToolCatalog::ListFunctions = QStringLiteral("list_functions");
const QString ToolCatalog::DecompileFunction = QStringLiteral("decompile_function");
const QString ToolCatalog::DisassembleFunction = QStringLiteral("disassemble_function");
const QString ToolCatalog::FindReferences = QStringLiteral("find_references");
const QString ToolCatalog::ListStrings = QStringLiteral("list_strings");
const QString ToolCatalog::ListImports = QStringLiteral("list_imports");
const QString ToolCatalog::GetCurrentLocation = QStringLiteral("get_current_location");

QJsonArray ToolCatalog::definitions()
{
    return QJsonArray {
        readOnlyTool(ListFunctions, "List functions",
                     "Lists the functions that the analysis found in the binary that is open in "
                     "the session. Returns the address, the name and the size of each function, "
                     "in the order of the addresses. Use filter, offset and limit when the binary "
                     "has many functions.",
                     listSchema("Keep only the functions whose name contains this text. The "
                                "comparison ignores case.")),
        readOnlyTool(DecompileFunction, "Decompile a function",
                     "Decompiles one function of the binary that is open in the session and "
                     "returns C-like pseudocode. The decompiler is rz-ghidra.",
                     functionSchema()),
        readOnlyTool(DisassembleFunction, "Disassemble a function",
                     "Disassembles one function of the binary that is open in the session. "
                     "Returns the address, the bytes and the text of each instruction, in the "
                     "order of the addresses.",
                     functionSchema()),
        readOnlyTool(FindReferences, "Find references",
                     "Finds the references that the analysis recorded for one address. The "
                     "direction \"to\" returns the references that point to the address, for "
                     "example the calls of a function. The direction \"from\" returns the "
                     "references that the instruction at the address makes.",
                     referenceSchema()),
        readOnlyTool(ListStrings, "List strings",
                     "Lists the strings that the analysis found in the binary that is open in "
                     "the session, in the order of the addresses. Each string has escape "
                     "sequences for the backslash, the double quote and control characters.",
                     listSchema("Keep only the strings that contain this text. The comparison "
                                "ignores case.")),
        readOnlyTool(ListImports, "List imports",
                     "Lists the functions that the binary imports from libraries. Returns the "
                     "name, the library and the address of each import. The address is null "
                     "when the import has no address.",
                     listSchema("Keep only the imports whose name or library contains this "
                                "text. The comparison ignores case.")),
        readOnlyTool(GetCurrentLocation, "Get the current location",
                     "Returns the address that the user looks at in the session window, and the "
                     "function that contains the address. The function is null when no function "
                     "contains the address.",
                     emptySchema())
    };
}

bool ToolCatalog::contains(const QString &name)
{
    const QJsonArray tools = definitions();
    for (const QJsonValue &tool : tools) {
        if (tool.toObject().value("name").toString() == name) {
            return true;
        }
    }
    return false;
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

QJsonObject ToolCatalog::listSchema(const QString &filterDescription)
{
    const QJsonObject filterProperty { { "type", "string" }, { "description", filterDescription } };
    const QJsonObject offsetProperty { { "type", "integer" },
                                       { "minimum", 0 },
                                       { "default", 0 },
                                       { "description",
                                         "Number of entries to skip, after the filter." } };
    const QJsonObject limitProperty { { "type", "integer" },
                                      { "minimum", 1 },
                                      { "maximum", MaxListLimit },
                                      { "default", DefaultListLimit },
                                      { "description", "Maximum number of entries to return." } };
    const QJsonObject properties { { "filter", filterProperty },
                                   { "offset", offsetProperty },
                                   { "limit", limitProperty } };
    return QJsonObject { { "type", "object" },
                         { "properties", properties },
                         { "additionalProperties", false } };
}

QJsonObject ToolCatalog::functionSchema()
{
    const QJsonObject functionProperty {
        { "type", "string" },
        { "description",
          "A function name from list_functions, or an address in the function. "
          "Write an address as hexadecimal with the 0x prefix, or as decimal." }
    };
    const QJsonObject properties { { "function", functionProperty } };
    const QJsonArray required { "function" };
    return QJsonObject { { "type", "object" },
                         { "properties", properties },
                         { "required", required },
                         { "additionalProperties", false } };
}

QJsonObject ToolCatalog::referenceSchema()
{
    const QJsonObject addressProperty {
        { "type", "string" },
        { "description",
          "An address, as hexadecimal with the 0x prefix, or as decimal. The other tools "
          "return addresses in this form." }
    };
    const QJsonArray directions { "to", "from" };
    const QJsonObject directionProperty { { "type", "string" },
                                          { "enum", directions },
                                          { "default", "to" },
                                          { "description",
                                            "The direction of the references to return." } };
    const QJsonObject properties { { "address", addressProperty },
                                   { "direction", directionProperty } };
    const QJsonArray required { "address" };
    return QJsonObject { { "type", "object" },
                         { "properties", properties },
                         { "required", required },
                         { "additionalProperties", false } };
}

QJsonObject ToolCatalog::emptySchema()
{
    return QJsonObject { { "type", "object" },
                         { "properties", QJsonObject() },
                         { "additionalProperties", false } };
}
