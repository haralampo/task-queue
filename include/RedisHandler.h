#include <memory>
#include <string>
#include <queue>
#include <iostream>
#include <sw/redis++/redis++.h>

class RedisHandler {
public:
    RedisHandler(const std::string& connection_str);
    void push_task(const std::string& queue_name, const std::string& task);
    std::optional<std::string> pop_task(const std::string& queue_name);

private:
    std::unique_ptr<sw::redis::Redis> _redis;
};