#include <sw/redis++/redis++.h>
#include <iostream>

using namespace sw::redis;

int main() {
    try {
        // Create an object that connects to the local Redis server
        auto redis = Redis("tcp://127.0.0.1:6379");

        // Set a key and get it back
        redis.set("status", "Redis is connected!");
        auto val = redis.get("status");

        if (val) {
            std::cout << *val << std::endl;
        }
    } catch (const Error &e) {
        std::cerr << "Redis Error: " << e.what() << std::endl;
    }
    return 0;
}