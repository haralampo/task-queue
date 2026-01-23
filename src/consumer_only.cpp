#include "RedisHandler.h"

using namespace std;
using namespace sw::redis;

int main() {

    RedisHandler redis_handler("tcp://127.0.0.1:6379");
    string queue = "queue";

    while (true) {
        // brpop returns an Optional<pair<string, string>> 
        // because it returns {list_name, value}
        optional<string> result = redis_handler.pop_task(queue);

        if (result == "SHUTDOWN") {
            cout << "Worker shutting down..." << endl;
            break;
        }
        cout << "Processing: " << result.value_or("No task acquired") << endl;
    }
}