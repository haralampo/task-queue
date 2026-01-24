#include <memory>
#include <string>
#include <queue>
#include <iostream>
#include <sw/redis++/redis++.h>
#include <string_view>
#include "json.h"
#include "task.h"


class RedisHandler {
public:
    RedisHandler(const std::string& connection_str);
    void push_task(const std::string& queue, const std::string& task);
    std::optional<std::string> pop_task(const std::string& queue);
    std::optional<std::string> pop_task_reliable(const std::string& source_queue, const std::string& dest_queue);
    void acknowledge_task(const std::string& proc_queue, const std::string& task_data);

private:
    std::unique_ptr<sw::redis::Redis> _redis;
};

class WorkerPool {
public:
    WorkerPool(const std::string& connection_str, int num_threads, const std::string& queue_name);
    ~WorkerPool();

private:
    RedisHandler _handler; 
    std::atomic<bool> _stop{false}; 
    std::vector<std::thread> _threads;
    std::string _queue;
};