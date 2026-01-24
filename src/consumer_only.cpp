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
        string_view sv = *result;

        if (nlohmann::json::accept(sv)) {
            nlohmann::json j = nlohmann::json::parse(sv);
            Task task(j);
            cout << "Task id = " << task.id << ", type = " << task.type << endl;
        }
        else {
            cout << "Invalid JSON" << endl;
            break;
        }
    }
}