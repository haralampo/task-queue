#include "RedisHandler.h"
#include "json.h"
#include "task.h"

using namespace std;
using namespace sw::redis;

int main() {
    // Create task
    // Convert from struct to json
    // Convery from json to string
    Task task{"101", "compute", "x=5"};
    nlohmann::json j = task;
    string s = j.dump();

    // Connect to Redis
    // Push task to queue
    RedisHandler redis_handler("tcp://127.0.0.1:6379");
    string queue = "queue";
    redis_handler.push_task(queue, s);

    redis_handler.push_task(queue, "SHUTDOWN");
}