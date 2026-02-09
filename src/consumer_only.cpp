#include "RedisHandler.h"
#include <atomic>
#include <csignal>

using namespace std;
using namespace sw::redis;

std::atomic<bool> keep_running(true);

void signal_handler(int signal) {
    keep_running = false;
}

int main() {
    // Catch Ctrl+C (SIGINT) and script's 'kill' (SIGTERM)
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    WorkerPool workerPool("tcp://127.0.0.1:6379?pool_size=11", 30, "queue");
    
    std::cout << "Consumer running. Waiting for tasks..." << std::endl;

    while (keep_running) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    std::cout << "Shutting down gracefully..." << std::endl;
    return 0;
}