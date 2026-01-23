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

int main() {

    thread t1(producer);
    t1.join();
    
}