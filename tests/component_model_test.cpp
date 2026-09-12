#include "component_model.hpp"

#include <cassert>
#include <iostream>

int main()
{
    Component component;

    component.id = "U1";
    component.type = "GENERIC";
    component.position = Point{10, 20, 0};

    component.pins.push_back(Pin{"A", Point{9, 20, 0}});

    component.pins.push_back(Pin{"Y", Point{11, 20, 0}});

    ComponentModel model;
    model.addComponent(component);

    Net net;
    net.name = "NET_IN";
    net.connect("U1", "A");

    model.addNet(net);

    Component* foundComponent = model.findComponent("U1");

    assert(foundComponent != nullptr);
    assert(foundComponent->id == "U1");

    Pin* foundPin = foundComponent->findPin("A");

    assert(foundPin != nullptr);
    assert((foundPin->position == Point{9, 20, 0}));

    Net* foundNet = model.findNet("NET_IN");

    assert(foundNet != nullptr);
    assert(foundNet->connections.size() == 1);

    assert(foundNet->connections[0].componentId == "U1");

    assert(foundNet->connections[0].pinName == "A");

    assert(model.findComponent("MISSING") == nullptr);
    assert(model.findNet("MISSING") == nullptr);
    assert(foundComponent->findPin("MISSING") == nullptr);

    std::cout << "Component: " << foundComponent->id << '\n';

    std::cout << "Pin: " << foundPin->name << " @ (" << foundPin->position.x
              << "," << foundPin->position.y << "," << foundPin->position.z
              << ")\n";

    std::cout << "Net: " << foundNet->name
              << " connections=" << foundNet->connections.size() << '\n';

    std::cout << "component_model test: PASS\n";

    return 0;
}
