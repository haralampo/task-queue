#include "RedisHandler.h"
#include "sw/redis++/command.h"
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

void RedisHandler::push_task(const string& queue, const string& task) {
    try {
        _redis->rpush(queue, task);
    } catch (const Error& err) {
        cerr << "Push failed: " << err.what() << endl;
    }
}

optional<string> RedisHandler::pop_task(const string& queue) {
    try {
        // brpop returns an Optional<pair<string, string>> 
        // {list_name, value}
        auto val = _redis->blpop(queue, chrono::seconds(1));
        if (val) { return val->second; }
    } 
    catch (const Error& err) {
        cerr << "Pop failed: " << err.what() << endl;
    }
    return nullopt;
}

optional<string> RedisHandler::pop_task_reliable(const string& source_queue, const string& dest_queue) {
    return _redis->blmove(source_queue, dest_queue, ListWhence::LEFT, ListWhence::RIGHT, chrono::seconds(1));
}

void RedisHandler::acknowledge_task(const string& proc_queue, const string& task_data) {
    _redis->lrem(proc_queue, 1, task_data);
}

WorkerPool::WorkerPool(const std::string& connection_str, int num_threads, const std::string& queue_name) : _handler(connection_str), _queue(queue_name) {
    for (int i = 0; i < num_threads; i++) {
        _threads.emplace_back([this, q_name = _queue] {
            string processing_queue = q_name + ":processing";
            while (!_stop) {
                auto result = _handler.pop_task_reliable(q_name, processing_queue);
                if (result.has_value()) {
                    string raw_data = std::move(result.value());

                    if (nlohmann::json::accept(raw_data)) {
                        auto j = nlohmann::json::parse(raw_data);
                        Task task(j);
                        cout << "Task id = " << task.id << ", type = " << task.type << endl;
                        _handler.acknowledge_task(processing_queue, raw_data);
                    }
                    else {
                        cerr << "Invalid JSON received, removing from processing queue." << endl;
                        _handler.acknowledge_task(processing_queue, raw_data);
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