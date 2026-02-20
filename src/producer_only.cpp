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
    const char* redis_env = std::getenv("REDIS_URL");
    std::string connection_str = redis_env ? redis_env : "tcp://127.0.0.1:6379";
    RedisHandler redis_handler(connection_str);
    string queue = "queue";
    string type = "EMAIL";

    int num_tasks = stoi(argv[1]);

    for (int i = 0; i < num_tasks; i++) {
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
        cout << "Sent Task " << i + 1 << endl;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    redis_handler.push_task(queue, "Hi, I'm an invalid JSON.");
}