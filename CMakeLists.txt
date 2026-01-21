cmake_minimum_required(VERSION 3.10)
project(RedisTaskQueue)

# Use C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 1. TELL CMAKE TO GENERATE THE JSON FOR CLANGD
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# This tells the compiler where to look for <sw/redis++/redis++.h>
include_directories(/usr/local/include)

# 2. Find the libraries
# Note: If on Mac Homebrew, we often need to hint where they are
find_library(REDIS_PLUS_LIB redis++)
find_library(HIREDIS_LIB hiredis)

# 3. Define your executable
# 4. Link the libraries to your executable
# --- EXECUTABLE 1: The Hello World Test ---
add_executable(hello hello_world.cpp)
target_link_libraries(hello PRIVATE ${REDIS_PLUS_LIB} ${HIREDIS_LIB} pthread)

# --- EXECUTABLE 2: Your Actual Task Queue ---
# add_executable(queue task_queue.cpp)
# target_link_libraries(queue PRIVATE ${REDIS_PLUS_LIB} ${HIREDIS_LIB} pthread)
