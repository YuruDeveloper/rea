#ifndef HTTPREQUEST_H
#define HTTPREQUEST_H

#include <QByteArray>
#include <QHash>

struct HttpRequest
{
    QByteArray method;
    QByteArray target;
    QHash<QByteArray, QByteArray> lowerCaseHeaders;
    QByteArray body;
};

#endif // HTTPREQUEST_H
