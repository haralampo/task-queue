#include "RedisHandler.h"
#include "json.h"

using namespace std;
using namespace sw::redis;

int main() {
    // Connect to Redis
    // Push task to queue
    RedisHandler redis_handler("tcp://127.0.0.1:6379");
    string queue = "queue";
    string type = "EMAIL";

    for (int i = 0; i < 1000; i++) {
        if (i % 3 == 1) {
            type = "CONVERT";
        }
        else if (i % 3 == 2) {
            type = "UPLOAD";
        }
        else {
            type = "EMAIL";
        }

        Task task{to_string(i + 1), type, "This is a payload."};
        nlohmann::json j = task;
        string s = j.dump();
        redis_handler.push_task(queue, s);
    }
}