# Distributed C++ Task Queue

This project implements a background job processing system in C++ that uses Redis to store and manage a task queue. A producer enqueues tasks in Redis, and a pool of worker threads retrieves and processes those tasks concurrently, allowing work to be executed asynchronously.

The system is designed with reliability and controlled concurrency in mind. Tasks move through explicit queue states so work is not lost if a worker crashes, and failed jobs are retried before eventually being moved to a dead-letter queue.

This design provides at-least-once task processing: tasks are acknowledged only after successful execution, ensuring work is not silently lost even if a worker crashes.

The project demonstrates how a lightweight distributed job queue can be built using Redis primitives, a thread pool, and careful handling of task state transitions.

---

# Architecture Overview

```
Producer
   │
   │ RPUSH
   ▼
Redis Queue (queue)
   │
   │ BLMOVE
   ▼
Processing Queue (queue:processing)
   │
   ▼
Worker Thread Pool
   │
   ├── success → remove task + record metrics
   └── failure → retry or move to dead-letter queue
```

---

# Tech Stack

**Language**
- C++20

**Libraries**
- Standard Template Library (STL)
- nlohmann/json for task serialization
- redis-plus-plus (Redis C++ client)

**Infrastructure**
- Redis (task broker)
- Docker / Docker Compose

**Build Tools**
- CMake

---

# Architecture Overview

The system consists of three main components.

### Producer

The producer generates tasks, serializes them to JSON, and pushes them into a Redis list that acts as the pending task queue.

The producer is intentionally simple. Its role is only to enqueue work so the behavior of the worker system can be observed independently.

---

### Redis

Redis stores the task queues that producers write to and workers read from.

Three queues are used:

| Queue | Purpose |
|------|--------|
| `queue` | pending tasks waiting to be processed |
| `queue:processing` | tasks currently claimed by workers |
| `queue:dead_letter` | tasks that failed after retry attempts |

Redis is well suited for this role because list operations are atomic and support blocking operations that allow workers to efficiently wait for new work.

---

### Worker Pool

The consumer process launches a fixed pool of worker threads that continuously retrieve tasks from Redis and execute them concurrently.

A thread pool is used to control concurrency and avoid the overhead of creating a new thread for each task. Worker threads are created once when the consumer starts and remain active for the lifetime of the process, repeatedly pulling tasks from the queue as they become available.

Limiting the number of worker threads prevents excessive thread creation and context switching while still allowing multiple tasks to be processed in parallel.

---

# Task Lifecycle

Tasks move through several states during their lifetime.

---

## 1. Enqueue

The producer creates a task and pushes it into the Redis queue using `RPUSH`.

This records the work that needs to be processed without executing the task immediately.

---

## 2. Claiming Work

Workers claim tasks using Redis `BLMOVE`, which atomically moves an item from:

```
queue  →  queue:processing
```

This operation blocks until work is available.

Using `BLMOVE` ensures the transfer between queues happens atomically. If a worker crashes after claiming a task, the task still exists in the processing queue and can be recovered.

---

## 3. Processing

Once claimed, the worker:

- parses the JSON payload
- simulates work
- measures processing latency
- records completion metrics

---

## 4. Retries

If task execution fails, the system retries the task up to three times.

The retry counter is incremented and the task is placed back into the main queue so another worker can attempt it.

This handles transient failures without losing work.

---

## 5. Dead Letter Queue

Tasks are moved to a dead-letter queue when:

- the retry limit is exceeded
- the payload cannot be parsed as valid JSON

Separating failed tasks prevents a permanently broken task from blocking the queue and allows failures to be inspected later.

---

# Reliability Mechanisms

### Atomic Queue Transitions

Redis `BLMOVE` ensures tasks are transferred between queues atomically. This prevents tasks from disappearing between the time they are claimed and processed.

---

### Crash Recovery

When the worker pool starts, it moves any leftover tasks in `queue:processing` back to the main queue.

These tasks may have been interrupted by a crash or forced shutdown.

---

### Delivery Guarantee

The system provides **at-least-once task processing**. Tasks are acknowledged only after successful completion. If a worker crashes during execution, the task remains in the processing queue and will be retried.

This means a task may run more than once, but it will not be silently lost.

---

# Metrics

Workers record simple performance metrics:

- completed task count
- total latency
- latency samples

Latency is measured from task creation time to completion. These metrics allow the system’s throughput and responsiveness to be evaluated during benchmarks.

---

# Project Structure

```
task-queue/
│
├── include/
│   ├── RedisHandler.h
│   ├── task.h
│   └── json.h
│
├── src/
│   ├── RedisHandler.cpp
│   └── main.cpp
│
├── scripts/
│   └── benchmark.sh
│
├── CMakeLists.txt
└── docker-compose.yml
```

---

# Building the Project

Install Redis development dependencies if needed.

```
sudo apt install libhiredis-dev
```

Build with CMake:

```
mkdir build
cd build
cmake ..
make
```

---

# Running the System

### Start Redis

```
redis-server
```

---

### Start Workers

Launch the consumer with a specified number of worker threads.

```
./consumer 10
```

---

### Produce Tasks

In another terminal:

```
./producer 5000
```

This generates tasks and pushes them into the Redis queue.

---

# Benchmarking

The benchmark script runs experiments with different worker counts and records latency and throughput metrics.

```
chmod +x scripts/benchmark.sh
./scripts/benchmark.sh
```

These experiments help evaluate how the system scales with increasing concurrency.

---

# Design Tradeoffs

The system prioritizes reliability and simplicity.

**At-least-once delivery**

Tasks may run more than once after crashes. This requires tasks to be idempotent in real production systems.

**Redis as a single coordination node**

Redis simplifies queue management but introduces a single point of failure. Production systems often use replication or distributed brokers.

**Fixed thread pool**

A fixed pool simplifies resource management but limits maximum concurrency to the configured worker count.

---

# Summary

This project demonstrates how to build a reliable background job system using C++, Redis, and multithreading. It highlights practical queue design patterns such as atomic task claiming, retry logic, dead-letter queues, and crash recovery while remaining small enough to understand end-to-end.