# Distributed C++ Task Queue

This project implements a background job processing system in C++ that uses Redis to store and manage a task queue. A producer enqueues tasks in Redis, and a pool of worker threads retrieves and processes those tasks concurrently, allowing work to be executed asynchronously.

The system is designed with reliability and controlled concurrency in mind. Tasks move through explicit queue states so work is not lost if a worker crashes, and failed jobs are retried before eventually being moved to a dead-letter queue.

This design provides at-least-once task processing: tasks are acknowledged only after successful execution, ensuring work is not silently lost even if a worker crashes.

The project demonstrates how a lightweight distributed job queue can be built using Redis primitives, a thread pool, and careful handling of task state transitions.

---

## Architecture Overview

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

## Tech Stack

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

## System Components

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
| `queue:dead_letter` | tasks that failed after retry attempts, or are of invalid format |

Redis is well suited for this role because list operations are atomic and support blocking operations that allow workers to efficiently wait for new work instead of periodically polling.

---

### Worker Pool

The consumer process launches a fixed pool of worker threads that remain active for the lifetime of the process, repeatedly pulling tasks from the queue as they become available. Limiting the number of worker threads reduces excessive context switching and improves CPU efficiency.

---

## Task Lifecycle

Tasks move through several states during their lifetime.

---

### 1. Enqueue

The producer creates a task and pushes it into the Redis queue using `RPUSH`. This records the work that needs to be processed without executing the task immediately.

---

### 2. Claiming Work

Workers claim tasks using Redis `BLMOVE`, which atomically moves an item from:

```
queue  →  queue:processing
```

This operation blocks until work is available.

Because `BLMOVE` performs the transfer atomically, a task will always exist in either the pending queue or the processing queue, even if a worker crashes during the operation.

---

### 3. Processing

Once claimed, the worker:

- Parses the JSON payload  
  - If the payload is invalid, the task is moved to the dead-letter queue.
- Simulates work  
  - If processing fails and the retry count is less than 3, the retry counter is incremented and the task is returned to the pending queue.  
  - If processing fails and the retry limit is exceeded, the task is moved to the dead-letter queue.
- Measures processing latency
- Records completion metrics

---

### 4. Retries

If task execution fails, the system retries the task up to three times. The retry counter is incremented and the task is placed back into the main queue so another worker can attempt it.

---

### 5. Dead Letter Queue

Tasks are moved to a dead-letter queue when:

- the retry limit is exceeded
- the payload cannot be parsed as valid JSON

Separating failed tasks prevents a permanently broken task from blocking the queue and allows failures to be inspected later.

---

## Reliability Mechanisms

### Atomic Queue Transitions

Redis `BLMOVE` ensures tasks are transferred between queues atomically. This prevents tasks from disappearing between the time they are claimed and processed.

---

### Crash Recovery

When the worker pool starts, it moves any leftover tasks in `queue:processing` back to the main queue. These tasks may have been interrupted by a crash or forced shutdown.

---

### Delivery Guarantee

The system provides **at-least-once task processing**. Tasks are acknowledged only after successful completion. If a worker crashes after claiming a task, the task remains in `queue:processing` and is returned to the pending queue on the next startup via the recovery step, allowing it to be processed again.

This means a task may run more than once, but it will not be silently lost.

---

## Metrics

Workers record simple performance metrics:

- completed task count
- total accumulated latency

Latency is measured from task creation time to completion. These metrics allow the system’s throughput and responsiveness to be evaluated during benchmarks.

---

## Project Structure

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
│   ├── main.cpp
│   ├── producer_only.cpp
│   └── consumer_only.cpp
│
├── scripts/
│   ├── benchmark.sh
│   └── scale_test.sh
│
├── CMakeLists.txt
└── docker-compose.yml
```

---

## Building the Project

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

## Running the System

You can run the system in *three ways*, depending on what you’re trying to do:

- *Locally (manual)*: best for development and debugging (fast iteration, direct control over the binaries).
- *Locally (convenience script)*: best for quick one-command local runs.
- *Docker Compose*: best for consistency and testing (reproducible environment, mirrors the benchmark scripts, easy scaling).

> Note: if the binaries are already up to date, you can comment out the build step in `scripts/run_system.sh` to speed up repeated runs. Re-enable it after changing source files or build configuration.

---

### Option A: Run Locally (manual development / debugging)

Use this when you want fast iteration, readable logs, and the ability to debug the C++ processes directly.

1) *Start Redis locally*
```bash
redis-server
```

2) *Optional: clear previous queue / metric state*
```bash
redis-cli DEL queue queue:processing queue:dead_letter completed_tasks total_latency_ms latency_count
```

This removes any leftover pending tasks, in-flight task markers, dead-letter entries, and metric counters from previous runs.

3) *Build the project*
```bash
cd build
cmake ..
make
cd ..
```

4) *Start the consumer (worker pool)*
```bash
./build/consumer 10
```
This launches one consumer process with a fixed pool of *10 worker threads* that continuously claim and process tasks.

5) *Run the producer* (in a second terminal)
```bash
./build/producer 5000
```
This enqueues *5000 tasks* into Redis. The worker threads process them asynchronously.

---

### Option B: Run Locally (convenience script)

Use this when you want a one-command local run without manually starting each component.

*Run:*
```bash
chmod +x scripts/run_system.sh
./scripts/run_system.sh
```

This helper script builds the project, resets Redis state, starts the consumer, runs the producer, and waits for the *pending queue* to empty before exiting.

---

### Option C: Run with Docker Compose (reproducible / benchmark-ready)

Use this when you want a consistent environment, containerized Redis, and the ability to scale worker processes easily.

1) *Build services*
```bash
docker compose build
```

2) *Start Redis and workers*
```bash
docker compose up -d redis worker
```

3) *Run the producer workload*
```bash
docker compose run --rm -T producer ./producer 5000
```

4) *Stop everything*
```bash
docker compose down
```

---

## Benchmarking and Scalability Testing

Two scripts are provided to evaluate performance. Both scripts run the system using *Docker Compose* so results are repeatable and easy to reproduce.

> Note: if the Docker images are already up to date, you can comment out the `docker compose build` step in the benchmark scripts to speed up repeated runs. Re-enable it after changing source files, Dockerfiles, or build configuration.

---

### Workload Benchmark (`scripts/benchmark.sh`)

This script runs a short deterministic test and produces a summary report plus logs.

*Run:*
```bash
chmod +x scripts/benchmark.sh
./scripts/benchmark.sh
```

*Outputs:*
- `logs/benchmark/producer.log` (producer output)
- `logs/benchmark/worker.log` (worker logs)
- `logs/benchmark/summary.txt` (printed summary report)

The summary includes:
- duration
- unique tasks successful
- retries attempted
- DLQ count
- average latency
- throughput

> Note: the script waits for the pending queue to empty, not for `queue:processing` to be empty. This avoids hanging if crashed workers leave stale in-flight entries behind.

---

### Horizontal Scalability Test (`scripts/scale_test.sh`)

This script measures how throughput and latency change as the number of worker *containers* increases.

*Run:*
```bash
chmod +x scripts/scale_test.sh
./scripts/scale_test.sh
```

*Metrics recorded per run:*
- throughput (tasks/sec)
- average latency (ms)
- duration (s)
- aggregate worker CPU (%)
- Redis CPU (%)
- throughput per worker (throughput / worker count)

*Output:*
- `logs/scale/results.csv`

---

### Plotting Scalability Results (`scripts/plot_results.py`)

After running the scale test, you can generate charts from the CSV results.

*Run:*
```bash
python3 scripts/plot_results.py
```

This script reads:

- `logs/scale/results.csv`

and generates:

- `logs/scale/total_throughput.png`
- `logs/scale/latency.png`
- `logs/scale/redis_cpu.png`
- `logs/scale/worker_cpu.png`
- `logs/scale/throughput_per_worker.png`

---

## Summary

This project demonstrates how to build a reliable background job system using C++, Redis, and multithreading. It highlights practical queue design patterns such as atomic task claiming, retry logic, dead-letter queues, and crash recovery while remaining small enough to understand end-to-end.