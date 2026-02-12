#include "RedisHandler.h"
#include "json.h"

using namespace std;
using namespace sw::redis;
using namespace std::chrono;

int main(int argc, char* argv[]) {

    if (argc < 2) {
        cerr << "Usage: " << argv[0] << " <count>" << endl;
        return 1;
    }

    // Connect to Redis
    // Push task to queue
    RedisHandler redis_handler("tcp://127.0.0.1:6379");
    string queue = "queue";
    string type = "EMAIL";

    int num_tasks = stoi(argv[1]);

    for (int i = 0; i < num_tasks - 1; i++) {
        if (i % 3 == 1) {
            type = "CONVERT";
        }
        else if (i % 3 == 2) {
            type = "UPLOAD";
        }
        else {
            type = "EMAIL";
        }

        long long now = duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
        Task task{to_string(i + 1), type, "Payload", 0, now};
        nlohmann::json j = task;
        string s = j.dump();
        redis_handler.push_task(queue, s);
    }
    redis_handler.push_task(queue, "Hi, I'm an invalid JSON.");
}