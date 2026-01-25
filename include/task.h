#include <string>
#include "json.h"

struct Task {
    std::string id;
    std::string type;
    std::string payload;
    int retries = 0;
};

NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Task, id, type, payload, retries);