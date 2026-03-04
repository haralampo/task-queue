#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Horizontal Scalability Benchmark
# --------------------------------------------------
# Purpose:
# - Run the same Docker workload repeatedly
# - Vary the number of worker containers
# - Measure throughput, latency, duration, and CPU
# - Save one CSV row per run
#
# Note:
# We only wait for "queue" to empty, then pause briefly.
# We do NOT require "queue:processing" to be empty because
# stale in-flight entries may remain after worker crashes.
# --------------------------------------------------

LOG_DIR="logs/scale"
RESULTS_FILE="${LOG_DIR}/results.csv"
mkdir -p "$LOG_DIR"
TASKS=2000
WORKER_COUNTS=(1 2 4 8 12 16)

# Bring everything down between runs and at the end
cleanup() {
  docker compose down --remove-orphans >/dev/null 2>&1 || true
}

# Wait until Redis is ready
wait_for_redis() {
  until docker exec "$(docker compose ps -q redis)" redis-cli ping | grep -q PONG; do
    sleep 0.2
  done
}

# Wait until the pending queue is empty
wait_for_queue_empty() {
  while [ "$(docker exec "$(docker compose ps -q redis)" redis-cli LLEN queue)" -gt 0 ]; do
    sleep 0.2
  done
}

mkdir -p "$LOG_DIR"

# Write CSV header
echo "worker_count,throughput,avg_latency_ms,duration_s,worker_cpu_percent,redis_cpu_percent,scaling_efficiency" > "$RESULTS_FILE"

echo "--- Building services ---"
docker compose build

echo "Starting Horizontal Scalability Study..."
echo "------------------------------------------"

for COUNT in "${WORKER_COUNTS[@]}"; do
  echo "Testing with $COUNT worker container(s)..."

  # Start from a clean environment each run
  cleanup

  # Start Redis first
  docker compose up -d redis >/dev/null
  wait_for_redis

  # Clear prior tasks + metrics
  docker exec "$(docker compose ps -q redis)" redis-cli FLUSHALL >/dev/null

  # Start the requested number of worker containers
  docker compose up -d --scale worker="$COUNT" worker >/dev/null

  # Time only the workload execution phase
  START_TIME=$(date +%s.%N)

  # Run fixed producer workload
  docker compose run --rm -T producer ./producer "$TASKS" > /dev/null

  # Wait until all pending tasks have been claimed
  wait_for_queue_empty

  # Brief grace period for final metrics to settle
  sleep 1
  END_TIME=$(date +%s.%N)

  # Read success + latency counters from Redis
  SUCCESS=$(docker exec "$(docker compose ps -q redis)" redis-cli SCARD completed_tasks)
  RAW_TOTAL_MS=$(docker exec "$(docker compose ps -q redis)" redis-cli GET total_latency_ms)
  RAW_COUNT=$(docker exec "$(docker compose ps -q redis)" redis-cli GET latency_count)

  totalms=${RAW_TOTAL_MS:-0}
  latcount=${RAW_COUNT:-0}

  duration=$(echo "$END_TIME - $START_TIME" | bc)

  if [ "$latcount" -gt 0 ]; then
    avg_lat=$(echo "scale=2; $totalms / $latcount" | bc)
  else
    avg_lat=0
  fi

  throughput=$(echo "scale=2; $SUCCESS / $duration" | bc)
  efficiency=$(echo "scale=4; $throughput / $COUNT" | bc)

  # Take one CPU snapshot after the run
  CPU_SNAPSHOT=$(docker stats --no-stream --format "{{.Name}} {{.CPUPerc}}")

  # Sum CPU across all worker containers
  CPU_WORKERS=$(echo "$CPU_SNAPSHOT" \
    | grep worker \
    | awk '{gsub(/%/, "", $2); sum += $2} END {print sum+0}')

  # Capture Redis CPU
  CPU_REDIS=$(echo "$CPU_SNAPSHOT" \
    | grep redis \
    | awk '{gsub(/%/, "", $2); print $2+0}')

  # Append one CSV row
  printf "%s,%s,%s,%s,%s,%s,%s\n" \
    "$COUNT" "$throughput" "$avg_lat" "$duration" "$CPU_WORKERS" "$CPU_REDIS" "$efficiency" >> "$RESULTS_FILE"

  echo "   Throughput: $throughput tasks/sec"
  echo "   Avg Latency: $avg_lat ms"
  echo "   Worker CPU: $CPU_WORKERS %"
  echo "   Redis CPU:  $CPU_REDIS %"
  echo ""
done

cleanup

echo "------------------------------------------"
echo "Scalability Study Complete."
echo "Results saved to $RESULTS_FILE"