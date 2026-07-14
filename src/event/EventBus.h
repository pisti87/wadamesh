#pragma once
#include "Event.h"
#include <functional>
#include <vector>

class EventBus {
public:
    static void init();

    static void subscribe(String type, std::function<void(Event)> handler);

    static void publish(Event event);

private:
    struct Subscriber {
        String type;
        std::function<void(Event)> handler;
    };

    static std::vector<Subscriber> subscribers;
};
