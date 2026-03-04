#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Local Convenience Runner
# --------------------------------------------------
# Purpose:
# - Build the project locally
# - Verify Redis is running
# - Clear old queue/metric state
# - Start one consumer process
# - Run the producer workload
# - Wait until the pending queue is empty
# - Allow a short grace period for workers to finish
#
# Note:
# We only wait for the main queue ("queue") to empty.
# We do NOT wait for "queue:processing" because crashed
# workers may leave stale entries there indefinitely.
# --------------------------------------------------

BUILD_DIR="build"
LOG_DIR="logs/local"
THREADS=10
TASKS=100

# Kill background jobs (like consumer) when script exits
cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Wait until no tasks remain in the pending queue.
# This means all queued work has been CLAIMED.
# It does not strictly guarantee every claimed task finished.
wait_for_queue_empty() {
  while [ "$(redis-cli LLEN queue)" -gt 0 ]; do
    sleep 0.2
  done
}

echo "--- Building project ---"

# Configure + build (from the build directory)
# Optional: rebuild only after source or build configuration changes.
# If the binaries are already up to date, you can comment out this block
# Re-enable it after editing C++ files, CMake configuration,
# or anything that affects the build.
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake ..
make
cd ..

echo "--- Checking local Redis ---"

# Require a locally running Redis instance
if ! redis-cli ping >/dev/null 2>&1; then
  echo "ERROR: Redis is not running locally."
  echo "Start it first with: redis-server"
  exit 1
fi

echo "--- Resetting Redis state ---"

# Clear only this project's keys
redis-cli DEL \
  queue \
  queue:processing \
  queue:dead_letter \
  completed_tasks \
  total_latency_ms \
  latency_count >/dev/null

mkdir -p "$LOG_DIR"

echo "--- Starting consumer (${THREADS} threads) ---"

# Start one consumer process in the background
"./${BUILD_DIR}/consumer" "$THREADS" > "${LOG_DIR}/consumer.log" 2>&1 &

# Small head start so consumer can connect first
sleep 0.5

echo "--- Running producer (${TASKS} tasks) ---"

# Run producer in foreground
"./${BUILD_DIR}/producer" "$TASKS" > "${LOG_DIR}/producer.log" 2>&1

echo "--- Waiting for pending queue to empty ---"
wait_for_queue_empty

# Give workers a brief chance to finish final metric writes
sleep 1

echo "--- Local run complete ---"
echo "Logs saved in ${LOG_DIR}/"