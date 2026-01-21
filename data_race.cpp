#include <chrono>
#include <string>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <iostream>
#include <queue>
using namespace std;

class SimpleQueue {
public:
    queue<string> queue;
    mutex mtx;
    condition_variable cv;

    void producer() {
        for (int i = 0; i < 10; i++) {
            {
                lock_guard<mutex> lock(mtx);
                queue.push("Task " + to_string(i + 1));
            }
            cv.notify_one();
        }
        lock_guard<mutex> lock(mtx);
        queue.push("SHUTDOWN");
        cv.notify_one();
    }

    void consumer() {
        while (true) {
            unique_lock<mutex> lock(mtx);
            cv.wait(lock, [this] {
                return !queue.empty();
            });

            string task = queue.front();
            queue.pop();
            lock.unlock();
            if (task == "SHUTDOWN") {
                return;
            }
            cout << "Processing: " << task << endl;
        }
    }
};

int counter = 0;
condition_variable cv;
bool ready = false;

void work() {
    for (int i = 0; i < 100000; i++) {
        counter++;
    }
}

int main() {
    SimpleQueue simpQueue;
    thread t1(&SimpleQueue::producer, &simpQueue);
    thread t2(&SimpleQueue::consumer, &simpQueue);

    t1.join();
    t2.join();
}