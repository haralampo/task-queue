#include "RedisHandler.h"
#include <chrono>
#include <thread>

using namespace std;
using namespace sw::redis;

int main() {
    RedisHandler rh("tcp://127.0.0.1:6379?pool_size=11");
    string q = "queue";

    while (true) {
        // This ANSI escape code clears the screen and moves the cursor to the top-left
        cout << "\033[2J\033[1;1H"; 

        cout << "========================================" << endl;
        cout << "       REDIS TASK QUEUE MONITOR         " << endl;
        cout << "========================================" << endl;
        cout << " PENDING:     " << rh.get_queue_size(q) << endl;
        cout << " PROCESSING:  " << rh.get_queue_size(q + ":processing") << endl;
        cout << " COMPLETED:   " << rh.get_completed_count("completed_tasks") << " (Unique)" << endl;
        cout << " DEAD LETTER: " << rh.get_queue_size(q + ":dead_letter") << endl;
        cout << "========================================" << endl;
        cout << " (Press Ctrl+C to exit) " << endl;

        this_thread::sleep_for(chrono::seconds(1));
    }
}