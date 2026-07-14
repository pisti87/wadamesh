#include "EventBus.h"

std::vector<EventBus::Subscriber> EventBus::subscribers;

void EventBus::init() {
    subscribers.clear();
}

void EventBus::subscribe(String type, std::function<void(Event)> handler) {
    subscribers.push_back({type, handler});
}

void EventBus::publish(Event event) {
    for (auto &s : subscribers) {
        if (s.type == event.type || s.type == "*") {
            s.handler(event);
        }
    }
}
