#!/bin/bash
# Tells the system to run this script using the Bash shell

set -e
# If ANY command fails (non-zero exit code), the script immediately exits.
# Prevents continuing with bad state.

trap 'kill 0' EXIT
# When the script exits (for any reason),
# kill all child processes started by this script.
# This prevents background processes (like consumer) from being left running.

echo "--- Compiling Project ---"

mkdir -p build
# Create a build directory if it doesn’t exist.
# -p prevents error if it already exists.

# Determine number of CPU cores
# On Mac: sysctl
# If both fail, fallback to 1
CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1)

# Compile the project
cd build && \
cmake .. > /dev/null && \      # Generate Makefiles (silence output)
make -j$CPU_CORES > /dev/null && \  # Compile using parallel jobs
cd ..
# -j$CPU_CORES = use all CPU cores for faster compilation

# --- Configuration ---
TOTAL_TASKS=5000
# Number of tasks the producer will send

THREADS_TO_TEST=(5 10 20 40)
# Array of thread counts to benchmark

echo ""
echo "Starting Benchmark Suite"
echo "Total Tasks: $TOTAL_TASKS"
echo "----------------------------------------"

# Loop over each thread configuration
for T in "${THREADS_TO_TEST[@]}"
do
    echo "Testing with $T threads..."

    # Clear Redis state before each test run
    redis-cli DEL queue queue:processing queue:dead_letter completed_tasks total_latency_ms latency_count > /dev/null

    # Start consumer in background with T worker threads
    ./build/consumer $T > /dev/null 2>&1 &
    CONSUMER_PID=$!
    # $! stores the PID of the last background process

    sleep 1
    # Give consumer time to start up

    START_TIME=$(date +%s)
    # Record start time (seconds since epoch)

    # Run producer (synchronously)
    ./build/producer $TOTAL_TASKS > /dev/null 2>&1

    TOTAL_PROCESSED=0

    # Poll Redis until all tasks are either completed or dead-lettered
    while [ $TOTAL_PROCESSED -lt $TOTAL_TASKS ]; do
        COMPLETED=$(redis-cli SCARD completed_tasks)
        # SCARD = size of set of completed tasks

        DEAD=$(redis-cli LLEN queue:dead_letter)
        # LLEN = length of dead-letter queue

        TOTAL_PROCESSED=$((COMPLETED + DEAD))

        # Print progress on same line
        echo -ne "  Progress: $TOTAL_PROCESSED / $TOTAL_TASKS\r"

        sleep 0.5
    done
    echo "" 

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    
    # Prevent division by zero
    if [ $ELAPSED -eq 0 ]; then ELAPSED=1; fi

    # Calculate throughput (tasks per second)
    TPS=$(echo "scale=2; $TOTAL_TASKS / $ELAPSED" | bc)

    # Fetch latency stats from Redis
    LAT_MS=$(redis-cli GET total_latency_ms || echo 0)
    LAT_COUNT=$(redis-cli GET latency_count || echo 1)

    # Ensure values exist
    LAT_MS=${LAT_MS:-0}
    LAT_COUNT=${LAT_COUNT:-1}

    # Average latency calculation
    AVG_LAT=$(echo "scale=2; $LAT_MS / $LAT_COUNT" | bc)

    echo "  >> Time: ${ELAPSED}s"
    echo "  >> TPS:  ${TPS} tasks/sec"
    echo "  >> Avg Task Latency: ${AVG_LAT}ms"
    echo "----------------------------------------"

    # Gracefully shut down consumer
    kill -TERM $CONSUMER_PID
    wait $CONSUMER_PID 2>/dev/null || true
    # wait avoids zombie process

    sleep 2
    # Extra cooldown so Redis/ports reset cleanly
done