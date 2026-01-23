#include <string>
#include "json.h"

struct Task {
    std::string id;
    std::string type;
    std::string payload;
};

NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Task, id, type, payload);