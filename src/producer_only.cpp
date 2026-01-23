#include "RedisHandler.h"

using namespace std;
using namespace sw::redis;

int main() {
    RedisHandler redis_handler("tcp://127.0.0.1:6379");
    string queue = "queue";

    for (int i = 0; i < 10; i++) {
        redis_handler.push_task(queue, "Task " + to_string(i + 1));
    }
    redis_handler.push_task(queue, "SHUTDOWN");
}