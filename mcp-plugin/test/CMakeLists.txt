cmake_minimum_required(VERSION 3.16)
project(rea-mcp-plugin-test LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Test)

set(CMAKE_AUTOMOC ON)
enable_testing()

add_executable(HttpRequestParserTest
    HttpRequestParserTest.cpp
    HttpRequestParserTest.h
    ../HttpRequest.h
    ../HttpRequestParser.cpp
    ../HttpRequestParser.h)
target_include_directories(HttpRequestParserTest PRIVATE ..)
target_link_libraries(HttpRequestParserTest PRIVATE Qt6::Core Qt6::Test)
add_test(NAME HttpRequestParserTest COMMAND HttpRequestParserTest)
