#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Docker Benchmark Smoke Test
# --------------------------------------------------
# Purpose:
# - Build images
# - Start Redis + workers
# - Run one fixed producer workload
# - Wait until the pending queue is empty
# - Allow a short grace period
# - Collect logs + summary metrics
#
# Note:
# We only wait for the main queue ("queue") to empty.
# We do NOT wait for "queue:processing" because crashed
# workers may leave stale entries there indefinitely.
# --------------------------------------------------

TASKS=100
LOG_DIR="logs/benchmark"
PRODUCER_LOG="${LOG_DIR}/producer.log"
WORKER_LOG="${LOG_DIR}/worker.log"
SUMMARY_LOG="${LOG_DIR}/summary.txt"

# Always clean up containers when the script exits
cleanup() {
  docker compose down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Wait until Redis responds to PING
wait_for_redis() {
  until docker exec "$(docker compose ps -q redis)" redis-cli ping | grep -q PONG; do
    sleep 0.2
  done
}

# Wait until no tasks remain in the pending queue
wait_for_queue_empty() {
  while [ "$(docker exec "$(docker compose ps -q redis)" redis-cli LLEN queue)" -gt 0 ]; do
    sleep 0.2
  done
}

mkdir -p "$LOG_DIR"

echo "--- Resetting environment ---"
docker compose down --remove-orphans >/dev/null 2>&1 || true

echo "--- Building services ---"
docker compose build

echo "--- Starting Redis and workers ---"
docker compose up -d redis worker >/dev/null

echo "--- Waiting for Redis readiness ---"
wait_for_redis

echo "--- Clearing Redis state ---"
docker exec "$(docker compose ps -q redis)" redis-cli FLUSHALL >/dev/null

echo "--- Running producer (${TASKS} tasks) ---"
START_TIME=$(date +%s.%N)
docker compose run --rm -T producer ./producer "$TASKS" > "$PRODUCER_LOG"

echo "--- Waiting for pending queue to empty ---"
wait_for_queue_empty

# Grace period for final worker processing / metric writes
sleep 1
END_TIME=$(date +%s.%N)

echo "--- Capturing worker logs ---"
docker compose logs worker --no-log-prefix --no-color > "$WORKER_LOG"

# Read summary metrics from Redis
UNIQUE_SUCCESS=$(docker exec "$(docker compose ps -q redis)" redis-cli SCARD completed_tasks)
DLQ_COUNT=$(docker exec "$(docker compose ps -q redis)" redis-cli LLEN queue:dead_letter)
RETRIES=$(grep -c "retry #" "$WORKER_LOG" || true)

RAW_TOTAL_MS=$(docker exec "$(docker compose ps -q redis)" redis-cli GET total_latency_ms)
RAW_COUNT=$(docker exec "$(docker compose ps -q redis)" redis-cli GET latency_count)

totalms=${RAW_TOTAL_MS:-0}
latcount=${RAW_COUNT:-0}

if [ "$latcount" -gt 0 ]; then
  AVG_LATENCY=$(echo "scale=2; $totalms / $latcount" | bc)
else
  AVG_LATENCY=0
fi

duration=$(echo "$END_TIME - $START_TIME" | bc)
throughput=$(echo "scale=2; $UNIQUE_SUCCESS / $duration" | bc)

# Producer sends TASKS normal tasks + 1 intentionally invalid payload
EXPECTED_TOTAL=$((TASKS + 1))

{
  echo "------------------------------------------"
  echo "Benchmark Results:"
  echo "  Duration:                   $(printf "%.3f" "$duration")s"
  echo "  Unique Tasks Successful:    $UNIQUE_SUCCESS"
  echo "  Total Retries Attempted:    $RETRIES"
  echo "  Tasks in Dead Letter (DLQ): $DLQ_COUNT"
  echo "  Average Task Latency:       ${AVG_LATENCY}ms"
  echo "  System Throughput:          ${throughput} tasks/sec"
  echo "------------------------------------------"
  echo "Total Tasks Accounted For:    $((UNIQUE_SUCCESS + DLQ_COUNT)) / $EXPECTED_TOTAL"
} | tee "$SUMMARY_LOG"

echo "Logs written to: $PRODUCER_LOG, $WORKER_LOG, $SUMMARY_LOG"