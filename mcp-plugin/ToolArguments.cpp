#include "ToolArguments.h"

#include "ToolCatalog.h"

#include <cmath>
#include <limits>

bool ToolArguments::parseAddress(const QString &text, quint64 *address)
{
    bool isAddress = false;
    *address = text.startsWith("0x", Qt::CaseInsensitive) ? text.mid(2).toULongLong(&isAddress, 16)
                                                          : text.toULongLong(&isAddress, 10);
    return isAddress;
}

bool ToolArguments::readList(const QJsonObject &arguments, QString *filter, qint64 *offset,
                             qint64 *limit, QString *errorMessage)
{
    const QJsonValue filterValue = arguments.value("filter");
    if (!filterValue.isString() && !filterValue.isUndefined()) {
        *errorMessage = "The argument \"filter\" must be a string.";
        return false;
    }
    *filter = filterValue.toString();
    *offset = 0;
    *limit = ToolCatalog::DefaultListLimit;
    if (!readInteger(arguments, "offset", 0, std::numeric_limits<qint32>::max(), offset)) {
        *errorMessage = "The argument \"offset\" must be an integer of 0 or more.";
        return false;
    }
    if (!readInteger(arguments, "limit", 1, ToolCatalog::MaxListLimit, limit)) {
        *errorMessage = QString("The argument \"limit\" must be an integer from 1 to %1.")
                                .arg(ToolCatalog::MaxListLimit);
        return false;
    }
    return true;
}

bool ToolArguments::readInteger(const QJsonObject &arguments, const QString &name, qint64 minimum,
                                qint64 maximum, qint64 *value)
{
    const QJsonValue argument = arguments.value(name);
    if (argument.isUndefined()) {
        return true;
    }
    const double number = argument.toDouble();
    if (!argument.isDouble() || number != std::floor(number)) {
        return false;
    }
    if (number < static_cast<double>(minimum) || number > static_cast<double>(maximum)) {
        return false;
    }
    *value = static_cast<qint64>(number);
    return true;
}
