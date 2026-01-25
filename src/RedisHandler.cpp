#include "RedisHandler.h"
#include "sw/redis++/command.h"
#include "sw/redis++/command_options.h"
#include <chrono>
#include <locale>
#include <memory>
#include <mutex>
#include <thread>

using namespace std;
using namespace sw::redis;

string INFO = "Info";
string ERROR = "Error";

random_device rd;
mt19937 gen(rd());
uniform_int_distribution<> distrib(1, 20);


RedisHandler::RedisHandler(const string& connection_str) : _redis(connection_str) {
    try {
        cout << "Connected to Redis!\n";
    }
    catch (Error& err) {
        cerr << "Redis Connection Failed: " << err.what() << "\n";
    }
}

void RedisHandler::push_task(const string& queue, const string& task) {
    try {
        _redis.rpush(queue, task);
    } catch (const Error& err) {
        cerr << "Push failed: " << err.what() << "\n";
    }
}

optional<string> RedisHandler::pop_task(const string& queue) {
    try {
        // brpop returns an Optional<pair<string, string>> 
        // {list_name, value}
        auto val = _redis.blpop(queue, chrono::seconds(1));
        if (val) { return val->second; }
    } 
    catch (const Error& err) {
        cerr << "Pop failed: " << err.what() << "\n";
    }
    return nullopt;
}

optional<string> RedisHandler::pop_task_reliable(const string& source_queue, const string& dest_queue) {
    return _redis.blmove(source_queue, dest_queue, ListWhence::LEFT, ListWhence::RIGHT, chrono::seconds(1));
}

void RedisHandler::acknowledge_task(const string& proc_queue, const string& task_data) {
    _redis.lrem(proc_queue, 1, task_data);
}

void RedisHandler::recover_tasks(const string& source, const string& destination) {
    try {
        // No blocking because we want to finish quickly
        while (auto val = _redis.lmove(source, destination, ListWhence::LEFT, ListWhence::RIGHT)) {
            cout << "Reaper: Recovered zombie task back to pending.\n";
        }
    } 
    catch (const Error& err) {
        cerr << "Reaper failure: " << err.what() << "\n";
    }
}

void RedisHandler::move_to_dlq(const string& source_queue, const string& dest_queue) {
    try {
        _redis.lmove(source_queue, dest_queue, ListWhence::LEFT, ListWhence::RIGHT);
    }
    catch (const Error& e) {
        cerr << "DLQ Move failed: " << e.what() << endl;
    }
}

void RedisHandler::retry_task(const string& proc_queue, const string& pending_q, const string& old_data, const string& new_data) {
    try {
        auto tx = _redis.transaction();
        tx.lrem(proc_queue, 1, old_data);
        tx.rpush(pending_q, new_data);
        tx.exec();
    }
    catch (const Error& e) {
        cerr << "Retry transaction failed: " << e.what() << endl;
    }
}

WorkerPool::WorkerPool(const std::string& connection_str, int num_threads, const std::string& queue_name) : _handler(connection_str), _queue(queue_name) {
    string pending_q = queue_name;
    string processing_q = queue_name + ":processing";

    _handler.recover_tasks(queue_name + ":processing", queue_name);

    for (int i = 0; i < num_threads; i++) {
        _threads.emplace_back([this, pending_q, processing_q] {

            while (!_stop) {
                // pop task from pending queue, move to processing queue
                auto result = _handler.pop_task_reliable(pending_q, processing_q);

                if (result.has_value()) {
                    string raw_data = std::move(result.value());

                    // if valid JSON
                    if (nlohmann::json::accept(raw_data)) {
                        auto j = nlohmann::json::parse(raw_data);
                        Task task = j.get<Task>();

                        int random_num = distrib(gen);
                        if (random_num % 3 == 0) {
                            if (task.retries < 3) {
                                task.retries++;
                                string retried_data = nlohmann::json(task).dump();
                                _handler.retry_task(processing_q, pending_q, raw_data, retried_data);
                                log("Processing task " + task.id + " failed, retry #" + to_string(task.retries), ERROR);
                            }
                            else {
                                _handler.move_to_dlq(processing_q, pending_q + ":dead_letter");
                                log("Task " + task.id + " exceeded retry limit, sending to dead letter queue.", ERROR);
                            }
                        }
                        else {
                            // successfully processed, remove task from processing queue
                            _handler.acknowledge_task(processing_q, raw_data);
                            log("Processed Task " + task.id + " (Type: " + task.type + ")", INFO);
                        }
                    }
                    else {
                        // move task from processing to dead letter
                        _handler.move_to_dlq(processing_q, pending_q + ":dead_letter");
                        log("Invalid JSON received, moving to dead letter queue.", ERROR);
                    }
                }
            }
            log("Thread shutting down.", INFO);
        });
    }
}

void WorkerPool::log(const string& message, const string& type) {
    auto now = chrono::system_clock::to_time_t(chrono::system_clock::now());
    struct tm time_struct; 
    localtime_r(&now, &time_struct);
    char time_str[20];
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", &time_struct);

    lock_guard<mutex> lock(_mtx);

    cout << "[" << time_str << "] "
         << "[" << type << "] "
         << "[Thread " << this_thread::get_id() << "] "
         << message << "\n";
}

WorkerPool::~WorkerPool() {
    _stop = true;
    for (auto& t : _threads) {
        t.join();
    }
}