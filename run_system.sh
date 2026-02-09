#!/bin/bash
trap 'kill 0' EXIT

redis-cli DEL queue queue:processing queue:dead_letter completed_tasks total_latency_ms latency_count

echo "Compiling project..."
cd build && cmake .. && make && cd ..

./build/monitor &
sleep 1

echo "Starting Producer..."
./build/producer

echo "Launching 10 consumers..."
for i in {1..3}; do
    ./build/consumer > "consumer_$i.log" 2>&1 &
    sleep 0.2 # Give each process a head start
done

echo "System running. Press Ctrl+C to stop everything."
wait