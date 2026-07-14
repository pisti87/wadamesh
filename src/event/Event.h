#pragma once
#include <Arduino.h>
#include <map>

struct Event {
    String type;
    String source;
    uint32_t timestamp;
    std::map<String, String> data;
};
