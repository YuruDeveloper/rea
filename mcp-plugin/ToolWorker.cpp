#include "ToolWorker.h"

#include "ToolArguments.h"
#include "ToolCatalog.h"
#include "ToolResult.h"

#include <QJsonArray>

#include <Cutter.h>
#include <algorithm>

void ToolWorker::runTool(quint64 callId, const QString &name, const QJsonObject &arguments)
{
    emit toolFinished(callId, callTool(name, arguments));
}

QJsonObject ToolWorker::callTool(const QString &name, const QJsonObject &arguments)
{
    if (name == ToolCatalog::ListFunctions) {
        return listFunctions(arguments);
    }
    if (name == ToolCatalog::DecompileFunction) {
        return decompileFunction(arguments);
    }
    if (name == ToolCatalog::DisassembleFunction) {
        return disassembleFunction(arguments);
    }
    if (name == ToolCatalog::FindReferences) {
        return findReferences(arguments);
    }
    if (name == ToolCatalog::ListStrings) {
        return listStrings(arguments);
    }
    if (name == ToolCatalog::ListImports) {
        return listImports(arguments);
    }
    if (name == ToolCatalog::GetCurrentLocation) {
        return getCurrentLocation();
    }
    return ToolResult::makeError("Unknown tool: " + name);
}

QJsonObject ToolWorker::listFunctions(const QJsonObject &arguments)
{
    QString filter;
    qint64 offset = 0;
    qint64 limit = 0;
    QString errorMessage;
    if (!ToolArguments::readList(arguments, &filter, &offset, &limit, &errorMessage)) {
        return ToolResult::makeError(errorMessage);
    }
    return ToolResult::makePage(collectFunctions(filter).values(), offset, limit, "functions");
}

QMap<quint64, QJsonObject> ToolWorker::collectFunctions(const QString &filter)
{
    QMap<quint64, QJsonObject> functionsByAddress;
    RzCoreLocked core(Core());
    const RzList *functions = rz_analysis_function_list(core->analysis);
    RzListIter *iterator = nullptr;
    RzAnalysisFunction *function = nullptr;
    CutterRzListForeach (functions, iterator, RzAnalysisFunction, function) {
        const QString name = QString::fromUtf8(function->name);
        if (!name.contains(filter, Qt::CaseInsensitive)) {
            continue;
        }
        QJsonObject entry;
        entry.insert("address", ToolResult::formatAddress(function->addr));
        entry.insert("name", name);
        entry.insert("size", static_cast<qint64>(rz_analysis_function_linear_size(function)));
        functionsByAddress.insert(function->addr, entry);
    }
    return functionsByAddress;
}

QJsonObject ToolWorker::decompileFunction(const QJsonObject &arguments)
{
    RzCoreLocked core(Core());
    QString errorMessage;
    const RzAnalysisFunction *function = findFunction(core, arguments, &errorMessage);
    if (!function) {
        return ToolResult::makeError(errorMessage);
    }

    const QString address = ToolResult::formatAddress(function->addr);
    const QString code = Core()->cmdRaw("pdg @ " + address);
    if (code.trimmed().isEmpty()) {
        return ToolResult::makeError("The decompiler returned no output for the function at "
                                     + address
                                     + ". Make sure that the rz-ghidra plugin is loaded.");
    }
    QJsonObject data;
    data.insert("address", address);
    data.insert("name", QString::fromUtf8(function->name));
    data.insert("decompiler", "rz-ghidra");
    data.insert("code", code);
    return ToolResult::makeData(data);
}

QJsonObject ToolWorker::disassembleFunction(const QJsonObject &arguments)
{
    RzCoreLocked core(Core());
    QString errorMessage;
    const RzAnalysisFunction *function = findFunction(core, arguments, &errorMessage);
    if (!function) {
        return ToolResult::makeError(errorMessage);
    }

    const QString address = ToolResult::formatAddress(function->addr);
    const CutterJson listing = Core()->cmdj("pdfj @ " + address);
    QJsonArray instructions;
    for (const CutterJson &operation : listing["ops"]) {
        const QString text = operation["disasm"].toString();
        QJsonObject entry;
        entry.insert("address", ToolResult::formatAddress(operation["offset"].toUt64()));
        entry.insert("bytes", operation["bytes"].toString());
        entry.insert("text", text.isEmpty() ? operation["opcode"].toString() : text);
        instructions.append(entry);
    }
    if (instructions.isEmpty()) {
        return ToolResult::makeError(
                "The disassembler returned no instructions for the function at " + address + ".");
    }
    QJsonObject data;
    data.insert("address", address);
    data.insert("name", QString::fromUtf8(function->name));
    data.insert("instructions", instructions);
    return ToolResult::makeData(data);
}

QJsonObject ToolWorker::findReferences(const QJsonObject &arguments)
{
    quint64 address = 0;
    if (!ToolArguments::parseAddress(arguments.value("address").toString(), &address)) {
        return ToolResult::makeError(
                "The argument \"address\" must be a string that contains an address, as "
                "hexadecimal with the 0x prefix, or as decimal.");
    }
    const QJsonValue directionValue = arguments.value("direction");
    const QString direction = directionValue.isUndefined() ? "to" : directionValue.toString();
    if (direction != "to" && direction != "from") {
        return ToolResult::makeError("The argument \"direction\" must be \"to\" or \"from\".");
    }

    const QList<XrefDescription> references = Core()->getXRefs(address, direction == "to", false);
    QJsonArray entries;
    for (const XrefDescription &reference : references) {
        QJsonObject entry;
        entry.insert("from", ToolResult::formatAddress(reference.from));
        entry.insert("fromName", reference.fromStr);
        entry.insert("to", ToolResult::formatAddress(reference.to));
        entry.insert("toName", reference.toStr);
        entry.insert("type", reference.type);
        entries.append(entry);
    }
    QJsonObject data;
    data.insert("address", ToolResult::formatAddress(address));
    data.insert("direction", direction);
    data.insert("references", entries);
    return ToolResult::makeData(data);
}

QJsonObject ToolWorker::listStrings(const QJsonObject &arguments)
{
    QString filter;
    qint64 offset = 0;
    qint64 limit = 0;
    QString errorMessage;
    if (!ToolArguments::readList(arguments, &filter, &offset, &limit, &errorMessage)) {
        return ToolResult::makeError(errorMessage);
    }

    QList<StringDescription> strings = Core()->getAllStrings(false);
    std::stable_sort(strings.begin(), strings.end(),
                     [](const StringDescription &left, const StringDescription &right) {
                         return left.vaddr < right.vaddr;
                     });
    QList<QJsonObject> matches;
    for (const StringDescription &string : strings) {
        if (!string.string.contains(filter, Qt::CaseInsensitive)) {
            continue;
        }
        QJsonObject entry;
        entry.insert("address", ToolResult::formatAddress(string.vaddr));
        entry.insert("string", string.string);
        entry.insert("encoding", string.type);
        entry.insert("length", static_cast<qint64>(string.length));
        entry.insert("section", string.section);
        matches.append(entry);
    }
    return ToolResult::makePage(matches, offset, limit, "strings");
}

QJsonObject ToolWorker::listImports(const QJsonObject &arguments)
{
    QString filter;
    qint64 offset = 0;
    qint64 limit = 0;
    QString errorMessage;
    if (!ToolArguments::readList(arguments, &filter, &offset, &limit, &errorMessage)) {
        return ToolResult::makeError(errorMessage);
    }

    const QList<ImportDescription> imports = Core()->getAllImports();
    QList<QJsonObject> matches;
    for (const ImportDescription &import : imports) {
        if (!import.name.contains(filter, Qt::CaseInsensitive)
            && !import.libname.contains(filter, Qt::CaseInsensitive)) {
            continue;
        }
        const bool hasAddress = import.plt != RVA_INVALID;
        QJsonObject entry;
        entry.insert("address", hasAddress ? ToolResult::formatAddress(import.plt) : QJsonValue());
        entry.insert("name", import.name);
        entry.insert("library", import.libname);
        entry.insert("type", import.type);
        matches.append(entry);
    }
    return ToolResult::makePage(matches, offset, limit, "imports");
}

QJsonObject ToolWorker::getCurrentLocation()
{
    RzCoreLocked core(Core());
    const quint64 address = core->offset;
    const RzAnalysisFunction *function = Core()->functionIn(address);
    QJsonObject data;
    data.insert("address", ToolResult::formatAddress(address));
    if (!function) {
        data.insert("function", QJsonValue());
        return ToolResult::makeData(data);
    }
    QJsonObject functionEntry;
    functionEntry.insert("address", ToolResult::formatAddress(function->addr));
    functionEntry.insert("name", QString::fromUtf8(function->name));
    data.insert("function", functionEntry);
    return ToolResult::makeData(data);
}

RzAnalysisFunction *ToolWorker::findFunction(RzCore *core, const QJsonObject &arguments,
                                             QString *errorMessage)
{
    const QString target = arguments.value("function").toString();
    if (target.isEmpty()) {
        *errorMessage = "The argument \"function\" must be a string that is not empty.";
        return nullptr;
    }
    const QByteArray targetName = target.toUtf8();
    RzAnalysisFunction *function =
            rz_analysis_get_function_byname(core->analysis, targetName.constData());
    if (function) {
        return function;
    }

    quint64 address = 0;
    if (ToolArguments::parseAddress(target, &address)) {
        function = Core()->functionIn(address);
        *errorMessage = "No function contains this address: " + target;
        return function;
    }

    QList<RzAnalysisFunction *> matches;
    RzListIter *iterator = nullptr;
    const RzList *functions = rz_analysis_function_list(core->analysis);
    CutterRzListForeach (functions, iterator, RzAnalysisFunction, function) {
        const RzFlagItem *flag = rz_flag_get(core->flags, function->name);
        if (flag && flag->realname && targetName == flag->realname) {
            matches.append(function);
        }
    }
    if (matches.size() == 1) {
        return matches.first();
    }
    *errorMessage = matches.isEmpty()
            ? "No function has this name: " + target
            : "More than one function has this name. Use an address in place of the name: "
                    + target;
    return nullptr;
}
