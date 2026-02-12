#include "RedisHandler.h"
#include <atomic>
#include <csignal>

using namespace std;
using namespace sw::redis;

std::atomic<bool> keep_running(true);

void signal_handler(int signal) {
    keep_running = false;
}

int main(int argc, char* argv[]) {

    if (argc < 2) {
        cerr << "Usage: " << argv[0] << " <count>" << endl;
        return 1;
    }

    // Catch Ctrl+C (SIGINT) and script's 'kill' (SIGTERM)
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    int num_threads = stoi(argv[1]);

    WorkerPool workerPool("tcp://127.0.0.1:6379?pool_size=" + to_string(num_threads + 2), num_threads, "queue");
    
    std::cout << "Consumer running. Waiting for tasks..." << std::endl;

    while (keep_running) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    std::cout << "Shutting down gracefully..." << std::endl;
    return 0;
}