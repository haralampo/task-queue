#include <chrono>
#include <string>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <iostream>
#include <queue>
#include <sw/redis++/redis++.h>

using namespace std;
using namespace sw::redis;

void consumer() {
    auto redis = Redis("tcp://127.0.0.1:6379");
    while (true) {
        // brpop returns an Optional<pair<string, string>> 
        // because it returns {list_name, value}
        auto result = redis.brpop("my_tasks");

        if (result) {
            string task = result->second; // The actual string
            if (task == "SHUTDOWN") {
                cout << "Worker shutting down..." << endl;
                break;
            }
            cout << "Processing: " << task << endl;
        }
    }
}

int main() {
    thread t2(consumer);
    t2.join();
}