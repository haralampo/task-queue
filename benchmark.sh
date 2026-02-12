#!/bin/bash

# Exit on error and cleanup background tasks on exit
set -e
trap 'kill 0' EXIT

echo "--- Compiling Project ---"

mkdir -p build
# Detect CPU cores for parallel build (Mac/Linux fallback)
CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1)

# Build binaries silently
cd build
cmake .. > /dev/null
make -j$CPU_CORES > /dev/null
cd ..

# --- Configuration ---
TOTAL_TASKS=5000
THREADS_TO_TEST=(5 10 20 40)

echo -e "\nStarting Benchmark Suite"
echo "Total Tasks: $TOTAL_TASKS"
echo "----------------------------------------"

for T in "${THREADS_TO_TEST[@]}"
do
    echo "Testing with $T threads..."

    # Reset Redis state
    redis-cli DEL queue queue:processing queue:dead_letter completed_tasks total_latency_ms latency_count > /dev/null

    # Start worker pool in background
    ./build/consumer $T > /dev/null 2>&1 &
    CONSUMER_PID=$!

    sleep 1 # Wait for initialization

    START_TIME=$(date +%s)
    ./build/producer $TOTAL_TASKS > /dev/null 2>&1

    # Poll until all tasks reach a terminal state (Completed or DLQ)
    TOTAL_PROCESSED=0
    while [ $TOTAL_PROCESSED -lt $TOTAL_TASKS ]; do
        COMPLETED=$(redis-cli SCARD completed_tasks)
        DEAD=$(redis-cli LLEN queue:dead_letter)
        TOTAL_PROCESSED=$((COMPLETED + DEAD))

        echo -ne "  Progress: $TOTAL_PROCESSED / $TOTAL_TASKS\r"
        sleep 0.5
    done
    echo "" 

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    [ $ELAPSED -eq 0 ] && ELAPSED=1 # Prevent div-by-zero

    # Calculate Performance Metrics
    TPS=$(echo "scale=2; $TOTAL_TASKS / $ELAPSED" | bc)
    LAT_MS=$(redis-cli GET total_latency_ms || echo 0)
    LAT_COUNT=$(redis-cli GET latency_count || echo 1)
    
    # Ensure numeric values for math
    LAT_MS=${LAT_MS:-0}
    LAT_COUNT=${LAT_COUNT:-1}
    AVG_LAT=$(echo "scale=2; $LAT_MS / $LAT_COUNT" | bc)

    echo "  >> Time: ${ELAPSED}s"
    echo "  >> TPS:  ${TPS} tasks/sec"
    echo "  >> Avg Task Latency: ${AVG_LAT}ms"
    echo "----------------------------------------"

    # Graceful shutdown of consumer
    kill -TERM $CONSUMER_PID
    wait $CONSUMER_PID 2>/dev/null || true

    sleep 2 # Cool-down to reclaim network ports
done