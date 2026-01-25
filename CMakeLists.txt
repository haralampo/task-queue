cmake_minimum_required(VERSION 3.10)
project(RedisTaskQueue)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Tell compiler where .h files are
include_directories(include)
include_directories(/usr/local/include)

# Find Redis libraries
find_library(REDIS_PLUS_LIB redis++)
find_library(HIREDIS_LIB hiredis)

# --- THE SHARED TOOLBOX ---
# Bundle RedisHandler logic so everyone can use it
add_library(task_lib src/RedisHandler.cpp)
target_link_libraries(task_lib PRIVATE ${REDIS_PLUS_LIB} ${HIREDIS_LIB} pthread)

# --- THE EXECUTABLES ---
# Link to "task_lib" instead of raw .cpp file
add_executable(hello src/hello_world.cpp)
target_link_libraries(hello PRIVATE task_lib ${REDIS_PLUS_LIB} ${HIREDIS_LIB} pthread)

add_executable(producer src/producer_only.cpp)
target_link_libraries(producer PRIVATE task_lib ${REDIS_PLUS_LIB} ${HIREDIS_LIB} pthread)

add_executable(consumer src/consumer_only.cpp)
target_link_libraries(consumer PRIVATE task_lib ${REDIS_PLUS_LIB} ${HIREDIS_LIB} pthread)

add_executable(monitor src/monitor.cpp)
target_link_libraries(monitor PRIVATE task_lib ${REDIS_PLUS_LIB} ${HIREDIS_LIB} pthread)