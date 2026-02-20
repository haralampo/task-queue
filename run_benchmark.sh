#!/usr/bin/env bash

# --------------------------------------------------
# Distributed Task Queue - Fast Deterministic Test
# --------------------------------------------------
# 1. Reset environment
# 2. Build services
# 3. Start infrastructure
# 4. Flush Redis
# 5. Run producer (start timer)
# 6. Wait for drain (stop timer)
# 7. Collect metrics and logs
# --------------------------------------------------


# 1. Reset environment (stop containers, remove orphans)
echo "--- Resetting Environment ---"
docker compose down --remove-orphans


# 2. Build services (use Docker cache)
echo "--- Compiling Project ---"
docker compose build


# 3. Start infrastructure (Redis + workers)
echo "--- Starting Redis and Workers ---"
docker compose up -d redis worker


# 4. Wait for Redis readiness and flush state
until docker exec $(docker compose ps -q redis) redis-cli ping | grep -q PONG; do
  sleep 0.5
done
docker exec $(docker compose ps -q redis) redis-cli FLUSHALL > /dev/null


# 5. Run producer and start timer
echo "--- Running Producer ---"
START_TIME=$(date +%s.%N)
docker compose run --rm -T producer ./producer 100 > producer_run.txt


# 6. Wait for queue drain and stop timer
echo "Waiting for workers to finish..."
while [ $(docker exec $(docker compose ps -q redis) redis-cli LLEN queue) -gt 0 ]; do
    sleep 0.5
done

# Allow final async writes to commit
sleep 2
END_TIME=$(date +%s.%N)


# 7. Capture worker logs
docker compose logs worker --no-log-prefix --no-color > worker_logs.txt


# --------------------------------------------------
# Metrics and Results
# --------------------------------------------------

# Retrieve task outcome metrics
UNIQUE_SUCCESS=$(docker exec $(docker compose ps -q redis) redis-cli SCARD completed_tasks)
DLQ_COUNT=$(docker exec $(docker compose ps -q redis) redis-cli LLEN queue:dead_letter)
RETRIES=$(grep -c "retry #" worker_logs.txt || echo "0")

# Retrieve latency aggregation metrics
RAW_TOTAL_MS=$(docker exec $(docker compose ps -q redis) redis-cli GET total_latency_ms)
RAW_COUNT=$(docker exec $(docker compose ps -q redis) redis-cli GET latency_count)
EXPECTED_TOTAL=$((100 + 1))


# Normalize missing Redis values
totalms=${RAW_TOTAL_MS:-0}
latcount=${RAW_COUNT:-0}


# Compute average latency (ms)
if [ "$latcount" -gt 0 ]; then
    AVG_LATENCY=$(echo "scale=2; $totalms / $latcount" | bc)
else
    AVG_LATENCY="0"
fi


# Compute duration and throughput
duration=$(echo "$END_TIME - $START_TIME" | bc)
throughput=$(echo "scale=2; $UNIQUE_SUCCESS / $duration" | bc)


# --------------------------------------------------
# Final Report
# --------------------------------------------------

echo "------------------------------------------"
echo "Benchmark Results:"
echo "  Duration:                   $(printf "%.3f" $duration)s"
echo "  Unique Tasks Successful:    $UNIQUE_SUCCESS"
echo "  Total Retries Attempted:    $RETRIES"
echo "  Tasks in Dead Letter (DLQ): $DLQ_COUNT"
echo "  Average Task Latency:       ${AVG_LATENCY}ms"
echo "  System Throughput:          ${throughput} tasks/sec"
echo "------------------------------------------"
echo "Total Tasks Accounted For:    $((UNIQUE_SUCCESS + DLQ_COUNT)) / $EXPECTED_TOTAL"