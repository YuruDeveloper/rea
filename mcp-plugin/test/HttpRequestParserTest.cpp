#include "HttpRequestParserTest.h"

#include "HttpRequestParser.h"

#include <QTest>

namespace {

const QByteArray PostBody = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}";

QByteArray makePost(const QByteArray &body)
{
    return "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAUTHORIZATION:  Bearer abc \r\n"
           "Content-Length: "
            + QByteArray::number(body.size()) + "\r\n\r\n" + body;
}

QByteArray makeGetWithHeadSize(qsizetype headSize)
{
    const QByteArray start = "GET /mcp HTTP/1.1\r\nX-Padding: ";
    return start + QByteArray(headSize - start.size(), 'x') + "\r\n\r\n";
}

}

void HttpRequestParserTest::readsRequestInOnePiece()
{
    HttpRequestParser parser;
    QCOMPARE(parser.feed(makePost(PostBody)), HttpRequestParser::Status::Ready);
    QCOMPARE(parser.request().method, QByteArray("POST"));
    QCOMPARE(parser.request().target, QByteArray("/mcp"));
    QCOMPARE(parser.request().lowerCaseHeaders.value("authorization"), QByteArray("Bearer abc"));
    QCOMPARE(parser.request().lowerCaseHeaders.value("host"), QByteArray("127.0.0.1"));
    QCOMPARE(parser.request().body, PostBody);
    QVERIFY(!parser.takeContinueRequest());
}

void HttpRequestParserTest::readsRequestSplitAtEachByte()
{
    const QByteArray request = makePost(PostBody);
    for (qsizetype split = 1; split < request.size(); split++) {
        HttpRequestParser parser;
        QCOMPARE(parser.feed(request.left(split)), HttpRequestParser::Status::NeedsMoreData);
        QCOMPARE(parser.feed(request.mid(split)), HttpRequestParser::Status::Ready);
        QCOMPARE(parser.request().body, PostBody);
    }
}

void HttpRequestParserTest::ignoresBytesAfterBody()
{
    HttpRequestParser parser;
    QCOMPARE(parser.feed(makePost(PostBody) + "GET /other HTTP/1.1\r\n\r\n"),
             HttpRequestParser::Status::Ready);
    QCOMPARE(parser.request().body, PostBody);
    QCOMPARE(parser.feed("more"), HttpRequestParser::Status::Ready);
    QCOMPARE(parser.request().target, QByteArray("/mcp"));
    QCOMPARE(parser.request().body, PostBody);
}

void HttpRequestParserTest::readsGetWithoutBody()
{
    HttpRequestParser parser;
    QCOMPARE(parser.feed("GET /mcp HTTP/1.0\r\nAccept: text/event-stream\r\n\r\n"),
             HttpRequestParser::Status::Ready);
    QCOMPARE(parser.request().method, QByteArray("GET"));
    QVERIFY(parser.request().body.isEmpty());
}

void HttpRequestParserTest::acceptsBodyAtLimit()
{
    const QByteArray body(HttpRequestParser::MaxBodyBytes, 'x');
    const QByteArray request = makePost(body);
    HttpRequestParser parser;
    QCOMPARE(parser.feed(request.left(request.size() - 1)),
             HttpRequestParser::Status::NeedsMoreData);
    QCOMPARE(parser.feed(request.right(1)), HttpRequestParser::Status::Ready);
    QCOMPARE(parser.request().body.size(), HttpRequestParser::MaxBodyBytes);
}

void HttpRequestParserTest::acceptsHeadAtLimit()
{
    HttpRequestParser parser;
    QCOMPARE(parser.feed(makeGetWithHeadSize(HttpRequestParser::MaxHeadBytes)),
             HttpRequestParser::Status::Ready);
}

void HttpRequestParserTest::rejectsHeadAboveLimit()
{
    HttpRequestParser parser;
    QCOMPARE(parser.feed(makeGetWithHeadSize(HttpRequestParser::MaxHeadBytes + 1)),
             HttpRequestParser::Status::Failed);
    QCOMPARE(parser.failureStatus(), 431);
}

void HttpRequestParserTest::rejectsHeadWithoutEnd()
{
    HttpRequestParser parser;
    QCOMPARE(parser.feed(QByteArray(HttpRequestParser::MaxHeadBytes, 'x')),
             HttpRequestParser::Status::NeedsMoreData);
    QCOMPARE(parser.feed("x"), HttpRequestParser::Status::Failed);
    QCOMPARE(parser.failureStatus(), 431);
}

void HttpRequestParserTest::requestsContinueOnce()
{
    HttpRequestParser parser;
    QCOMPARE(parser.feed("POST /mcp HTTP/1.1\r\nExpect: 100-Continue\r\nContent-Length: 2\r\n\r\n"),
             HttpRequestParser::Status::NeedsMoreData);
    QVERIFY(parser.takeContinueRequest());
    QVERIFY(!parser.takeContinueRequest());
    QCOMPARE(parser.feed("{}"), HttpRequestParser::Status::Ready);
    QVERIFY(!parser.takeContinueRequest());
}

void HttpRequestParserTest::keepsFailureAfterMoreData()
{
    HttpRequestParser parser;
    QCOMPARE(parser.feed("POST /mcp HTTP/1.1\r\n\r\n"), HttpRequestParser::Status::Failed);
    QCOMPARE(parser.feed(makePost(PostBody)), HttpRequestParser::Status::Failed);
    QCOMPARE(parser.failureStatus(), 411);
}

void HttpRequestParserTest::rejectsBadHead_data()
{
    QTest::addColumn<QByteArray>("request");
    QTest::addColumn<int>("expectedStatus");

    const QByteArray aboveLimit = QByteArray::number(HttpRequestParser::MaxBodyBytes + 1);
    QTest::newRow("request line with two parts") << QByteArray("POST /mcp\r\n\r\n") << 400;
    QTest::newRow("request line with four parts")
            << QByteArray("POST /mcp extra HTTP/1.1\r\n\r\n") << 400;
    QTest::newRow("protocol that is not HTTP/1")
            << QByteArray("POST /mcp HTTP/2\r\nContent-Length: 0\r\n\r\n") << 400;
    QTest::newRow("header line without a colon")
            << QByteArray("GET /mcp HTTP/1.1\r\nNoColon\r\n\r\n") << 400;
    QTest::newRow("header line without a name")
            << QByteArray("GET /mcp HTTP/1.1\r\n: value\r\n\r\n") << 400;
    QTest::newRow("POST without a length") << QByteArray("POST /mcp HTTP/1.1\r\n\r\n") << 411;
    QTest::newRow("transfer encoding")
            << QByteArray("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") << 501;
    QTest::newRow("length that is not a number")
            << QByteArray("POST /mcp HTTP/1.1\r\nContent-Length: abc\r\n\r\n") << 400;
    QTest::newRow("negative length")
            << QByteArray("POST /mcp HTTP/1.1\r\nContent-Length: -1\r\n\r\n") << 400;
    QTest::newRow("length above the limit")
            << QByteArray("POST /mcp HTTP/1.1\r\nContent-Length: " + aboveLimit + "\r\n\r\n")
            << 413;
}

void HttpRequestParserTest::rejectsBadHead()
{
    QFETCH(QByteArray, request);
    QFETCH(int, expectedStatus);

    HttpRequestParser parser;
    QCOMPARE(parser.feed(request), HttpRequestParser::Status::Failed);
    QCOMPARE(parser.failureStatus(), expectedStatus);
    QVERIFY(!parser.takeContinueRequest());
}

QTEST_APPLESS_MAIN(HttpRequestParserTest)
