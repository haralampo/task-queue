#include "RedisHandler.h"

#include <memory>
#include <string>
#include <queue>
#include <iostream>
#include <sw/redis++/redis++.h>

using namespace std;
using namespace sw::redis;

RedisHandler::RedisHandler(const string& connection_str) {
    try {
        _redis = make_unique<Redis>(connection_str);
        cout << "Connected to Redis!" << endl;
    }
    catch (Error& err) {
        cerr << "Redis Connection Failed: " << err.what() << endl;
    }
}

void RedisHandler::push_task(const string& queue_name, const string& task) {
    try {
        _redis->rpush(queue_name, task);
    } catch (const Error& err) {
        cerr << "Push failed: " << err.what() << endl;
    }
}

optional<string> RedisHandler::pop_task(const string& queue_name) {
    try {
        auto val = _redis->blpop(queue_name);
        if (val) { return val->second; }
    } 
    catch (const Error& err) {
        cerr << "Pop failed: " << err.what() << endl;
    }
    return nullopt;
}