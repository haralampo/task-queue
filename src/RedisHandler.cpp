#include "RedisHandler.h"
#include <chrono>
#include <memory>

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
        // brpop returns an Optional<pair<string, string>> 
        // {list_name, value}
        auto val = _redis->blpop(queue_name, chrono::seconds(1));
        if (val) { return val->second; }
    } 
    catch (const Error& err) {
        cerr << "Pop failed: " << err.what() << endl;
    }
    return nullopt;
}

WorkerPool::WorkerPool(const std::string& connection_str, int num_threads, const std::string& queue_name) : _handler(connection_str), _queue(queue_name) {
    for (int i = 0; i < num_threads; i++) {
        _threads.emplace_back([this, q_name = _queue] {
            while (!_stop) {
                auto result = _handler.pop_task(q_name);
                if (result.has_value()) {
                    string raw_data = std::move(result.value());

                    if (nlohmann::json::accept(raw_data)) {
                        auto j = nlohmann::json::parse(raw_data);
                        Task task(j);
                        cout << "Task id = " << task.id << ", type = " << task.type << endl;
                    }
                }
            }
            cout << "Stopping threads gracefully" << endl;
        });
    }
}

WorkerPool::~WorkerPool() {
    _stop = true;
    for (auto& t : _threads) {
        t.join();
    }
}