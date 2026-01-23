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

class SimpleQueue {
public:

    void producer() {
        // Opens TCP socket to Redis process, 6379 is Redis port
        auto redis = Redis("tcp://127.0.0.1:6379");
        for (int i = 0; i < 10; i++) {
            string task = "Task " + to_string(i + 1);
            // LPUSH adds to the "left" of the list
            redis.lpush("my_tasks", task); 
            cout << "Sent: " << task << endl;
        }
        redis.lpush("my_tasks", "SHUTDOWN");
    }

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
};

int main() {
    SimpleQueue simpQueue;
    thread t1(&SimpleQueue::producer, &simpQueue);
    thread t2(&SimpleQueue::consumer, &simpQueue);

    t1.join();
    t2.join();
}