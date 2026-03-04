import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

# --------------------------------------------------
# Scale Test Plot Generator
# --------------------------------------------------
# Reads the CSV produced by scripts/scale_test.sh and
# generates charts in the same logs/scale directory.
# --------------------------------------------------

OUTPUT_DIR = Path("logs/scale")
CSV_PATH = OUTPUT_DIR / "results.csv"

if not CSV_PATH.exists():
    raise FileNotFoundError(
        f"Could not find {CSV_PATH}. Run scripts/scale_test.sh first."
    )

# Load results
df = pd.read_csv(CSV_PATH)

# Ensure numeric columns are treated as numbers
numeric_columns = [
    "worker_count",
    "throughput",
    "avg_latency_ms",
    "duration_s",
    "worker_cpu_percent",
    "redis_cpu_percent",
    "scaling_efficiency",
]

for col in numeric_columns:
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors="coerce")

# Drop rows with missing worker_count since plotting depends on it
df = df.dropna(subset=["worker_count"])

def save_plot(x, y, xlabel, ylabel, title, output_name):
    plt.figure()
    plt.plot(x, y, marker="o")
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)
    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / output_name)
    plt.close()

# Plot Throughput vs Worker Count
save_plot(
    df["worker_count"],
    df["throughput"],
    "Worker Count",
    "Throughput (tasks/sec)",
    "Throughput vs Worker Count",
    "throughput.png",
)

# Plot Latency vs Worker Count
save_plot(
    df["worker_count"],
    df["avg_latency_ms"],
    "Worker Count",
    "Average Latency (ms)",
    "Latency vs Worker Count",
    "latency.png",
)

# Plot Redis CPU vs Worker Count
save_plot(
    df["worker_count"],
    df["redis_cpu_percent"],
    "Worker Count",
    "Redis CPU (%)",
    "Redis CPU vs Worker Count",
    "redis_cpu.png",
)

# Plot Worker CPU vs Worker Count
save_plot(
    df["worker_count"],
    df["worker_cpu_percent"],
    "Worker Count",
    "Aggregate Worker CPU (%)",
    "Worker CPU vs Worker Count",
    "worker_cpu.png",
)

# Plot Scaling Efficiency vs Worker Count
if "scaling_efficiency" in df.columns:
    save_plot(
        df["worker_count"],
        df["scaling_efficiency"],
        "Worker Count",
        "Tasks/sec per Worker",
        "Throughput per Worker vs Worker Count",
        "throughput_per_worker.png",
    )

print("Graphs generated:")
print(" - logs/scale/throughput.png")
print(" - logs/scale/latency.png")
print(" - logs/scale/redis_cpu.png")
print(" - logs/scale/worker_cpu.png")
if "scaling_efficiency" in df.columns:
    print(" - logs/scale/efficiency.png")