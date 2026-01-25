#include "RedisHandler.h"

using namespace std;
using namespace sw::redis;

int main() {
    WorkerPool workerPool("tcp://127.0.0.1:6379?pool_size=11", 10, "queue");
    cin.get();
}