# Distributed C++ Task Queue

Distributed C++ Task Queue is a high-concurrency background processing system that uses a custom **RAII-based thread pool** and **Redis** to manage asynchronous tasks with "at-least-once" delivery guarantees.

## Tech Stack

**Language & Core:**

* C++20
* Standard Template Library (STL)
* `nlohmann/json` (Serialization)

**Middleware:**

* Redis (Message Broker & State Store)
* `redis-plus-plus` (C++ Client)

**DevOps & Tooling:**

* Docker & Docker Compose
* CMake (Build System)
* Shell Scripting (Benchmarking)

## Architecture Overview

**Producer (C++ CLI)** ↓ `RPUSH` / `JSON`

**Redis (List/Sets)**

↓ `BLMOVE` (Atomic)

**Worker Pool (C++ Thread Pool)**

* **Atomic Transitions:** Workers use `BLMOVE` to move tasks from `PENDING` to `PROCESSING`. This ensures that if a worker crashes, the task isn't lost—it remains in the processing list for recovery.
* **RAII Lifecycle:** The `WorkerPool` destructor automatically sets a stop flag and joins all worker threads, preventing resource leaks.
* **Dead Letter Queue (DLQ):** Tasks that exceed the retry limit (3 attempts) or contain invalid JSON are automatically moved to a `:dead_letter` queue for manual inspection.

## Project Structure

```text
task-queue/
├── include/
│   ├── json.h            # JSON library wrapper
│   ├── RedisHandler.h    # Redis client and WorkerPool definitions
│   └── task.h            # Task struct and serialization macros
├── src/
│   ├── main.cpp          # Entry point for Producer/Consumer logic
│   └── RedisHandler.cpp  # Atomic pop, transactions, and worker logic
├── scripts/
│   └── benchmark.sh      # Automated performance testing suite
├── CMakeLists.txt        # Build configuration
└── docker-compose.yml    # Cluster orchestration (Redis + 3 Workers)
```

## Environment Variables

The system connects to Redis via a connection string. In a Docker environment, ensure the following is accessible:

**`REDIS_URL="tcp://redis:6379"`**

* For local development, this usually defaults to `tcp://127.0.0.1:6379`.

## Installation

### 1. Install Dependencies

You will need `hiredis` and `redis-plus-plus` installed on your system:

```bash
# Ubuntu/Debian example
sudo apt-get install libhiredis-dev
# Install redis-plus-plus from source (recommended)

```

### 2. Build the Project

```bash
mkdir build && cd build
cmake ..
make -j$(nproc)

```

## Running the Application

### Start the Worker Pool (Consumer)

Run the consumer with the desired number of threads (e.g., 10 threads):

```bash
./build/consumer 10

```

### Dispatch Tasks (Producer)

In a separate terminal, send tasks to the queue:

```bash
./build/producer 5000

```

### Run Performance Benchmarks

The included benchmark script automates the setup, execution, and metric collection:

```bash
chmod +x benchmark.sh
./benchmark.sh

```

The script tests various thread counts (5, 10, 20, 40) and reports **Tasks Per Second (TPS)** and **Average Latency**.

## Reliability Features

* **Zombie Recovery:** On startup, the `WorkerPool` calls `recover_tasks` to move orphaned items from the `:processing` list back to the main queue.
* **Thread Safety:** All console logging and shared state transitions are protected by `std::mutex` and `std::lock_guard`.
* **At-Least-Once:** Tasks are only "Acknowledge" (removed from Redis) after successful processing logic is completed.