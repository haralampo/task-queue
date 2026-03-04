# Stage 1: The Builder
# We MUST name this "builder" so the next stage can find it
FROM gcc:13 as builder

RUN apt-get update && apt-get install -y \
    cmake \
    libhiredis-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install redis-plus-plus
WORKDIR /tmp
RUN git clone https://github.com/sewenew/redis-plus-plus.git && \
    cd redis-plus-plus && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make && \
    make install

# Build the app
WORKDIR /app
COPY . .
RUN mkdir -p build && cd build && cmake .. && make -j$(nproc)

# Stage 2: The Runtime
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy redis-plus-plus from the "builder" stage
COPY --from=builder /usr/local/lib/libredis++* /usr/local/lib/
# Copy the hiredis library that was installed in the "builder" stage
COPY --from=builder /usr/lib/x86_64-linux-gnu/libhiredis* /usr/local/lib/

RUN ldconfig

WORKDIR /root/
COPY --from=builder /app/build/consumer .
COPY --from=builder /app/build/producer .

CMD ["./consumer", "5"]