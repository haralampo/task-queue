#!/usr/bin/env bash
set -e

# --------------------------------------------------
# Horizontal Scalability Benchmark
# --------------------------------------------------
# Measures:
# - Throughput (tasks/sec)
# - Average task latency (ms)
# - Total duration (s)
# - Aggregate worker CPU (%)
# - Redis CPU (%)
# --------------------------------------------------

RESULTS_FILE="scalability_results.csv"
echo "worker_count,throughput,avg_latency_ms,duration_s,worker_cpu_percent,redis_cpu_percent,scaling_efficiency" > "$RESULTS_FILE"

WORKER_COUNTS=(1 2 4 8 12 16)

docker compose build

echo "Starting Horizontal Scalability Study..."
echo "------------------------------------------"

for COUNT in "${WORKER_COUNTS[@]}"
do
    echo "Testing with $COUNT workers..."

    # --------------------------------------------------
    # Reset environment
    # --------------------------------------------------
    docker compose down --remove-orphans > /dev/null 2>&1
    docker compose up -d redis > /dev/null 2>&1

    # Wait for Redis readiness
    until docker exec $(docker compose ps -q redis) redis-cli ping | grep -q PONG; do
        sleep 0.2
    done

    docker exec $(docker compose ps -q redis) redis-cli FLUSHALL > /dev/null

    # --------------------------------------------------
    # Scale workers
    # --------------------------------------------------
    docker compose up -d --scale worker=$COUNT worker > /dev/null 2>&1

    # --------------------------------------------------
    # Run workload benchmark
    # --------------------------------------------------
    START_TIME=$(date +%s.%N)

    docker compose run --rm -T producer ./producer 2000 > /dev/null 2>&1

    # Wait for queue drain
    while [ $(docker exec $(docker compose ps -q redis) redis-cli LLEN queue) -gt 0 ]; do
        sleep 0.2
    done

    # Allow final async metric writes
    sleep 1
    END_TIME=$(date +%s.%N)

    # --------------------------------------------------
    # Collect workload metrics
    # --------------------------------------------------
    SUCCESS=$(docker exec $(docker compose ps -q redis) redis-cli SCARD completed_tasks)
    RAW_TOTAL_MS=$(docker exec $(docker compose ps -q redis) redis-cli GET total_latency_ms)
    RAW_COUNT=$(docker exec $(docker compose ps -q redis) redis-cli GET latency_count)

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

    # --------------------------------------------------
    # Collect CPU metrics (snapshot)
    # --------------------------------------------------

    CPU_SNAPSHOT=$(docker stats --no-stream --format "{{.Name}} {{.CPUPerc}}")

    CPU_WORKERS=$(echo "$CPU_SNAPSHOT" \
        | grep worker \
        | awk '{gsub(/%/, "", $2); sum += $2} END {print sum+0}')

    CPU_REDIS=$(echo "$CPU_SNAPSHOT" \
        | grep redis \
        | awk '{gsub(/%/, "", $2); print $2+0}')

    # --------------------------------------------------
    # Save results
    # --------------------------------------------------
    echo "$COUNT,$throughput,$avg_lat,$duration,$CPU_WORKERS,$CPU_REDIS" >> "$RESULTS_FILE"

    echo "   Done:"
    echo "      Throughput: $throughput tasks/sec"
    echo "      Avg Latency: $avg_lat ms"
    echo "      Worker CPU: $CPU_WORKERS %"
    echo "      Redis CPU:  $CPU_REDIS %"
    echo ""
done

echo "------------------------------------------"
echo "Scalability Study Complete."
echo "Results saved to $RESULTS_FILE"