#ifndef HTTPREQUESTPARSERTEST_H
#define HTTPREQUESTPARSERTEST_H

#include <QObject>

class HttpRequestParserTest : public QObject
{
    Q_OBJECT

private slots:
    void readsRequestInOnePiece();
    void readsRequestSplitAtEachByte();
    void ignoresBytesAfterBody();
    void readsGetWithoutBody();
    void acceptsBodyAtLimit();
    void acceptsHeadAtLimit();
    void rejectsHeadAboveLimit();
    void rejectsHeadWithoutEnd();
    void requestsContinueOnce();
    void keepsFailureAfterMoreData();
    void rejectsBadHead_data();
    void rejectsBadHead();
};

#endif // HTTPREQUESTPARSERTEST_H
