import pandas as pd
import matplotlib.pyplot as plt

# Load results
df = pd.read_csv("scalability_results.csv")

# Create figure
plt.figure()

# Plot Throughput vs Worker Count
plt.plot(df["worker_count"], df["throughput"], marker="o")

plt.xlabel("Worker Count")
plt.ylabel("Throughput (tasks/sec)")
plt.title("Throughput vs Worker Count")

plt.tight_layout()
plt.savefig("throughput_vs_workers.png")
plt.close()


# Plot Latency vs Worker Count
plt.figure()

plt.plot(df["worker_count"], df["avg_latency_ms"], marker="o")

plt.xlabel("Worker Count")
plt.ylabel("Average Latency (ms)")
plt.title("Latency vs Worker Count")

plt.tight_layout()
plt.savefig("latency_vs_workers.png")
plt.close()


# Plot Redis CPU vs Worker Count
plt.figure()

plt.plot(df["worker_count"], df["redis_cpu_percent"], marker="o")

plt.xlabel("Worker Count")
plt.ylabel("Redis CPU (%)")
plt.title("Redis CPU vs Worker Count")

plt.tight_layout()
plt.savefig("redis_cpu_vs_workers.png")
plt.close()


print("Graphs generated:")
print(" - throughput_vs_workers.png")
print(" - latency_vs_workers.png")
print(" - redis_cpu_vs_workers.png")