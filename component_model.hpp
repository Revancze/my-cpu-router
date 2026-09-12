#pragma once

#include "net_id.hpp"
#include "router.hpp"

#include <string>
#include <vector>


// ============================================================
// PIN
// ============================================================

struct Pin
{
    std::string name;
    Point position;
};


// ============================================================
// COMPONENT
// ============================================================

struct Component
{
    std::string id;
    std::string type;

    Point position;

    std::vector<Pin> pins;

    Pin* findPin(const std::string& name);

    const Pin* findPin(const std::string& name) const;
};


// ============================================================
// NET CONNECTION
// ============================================================

struct NetConnection
{
    std::string componentId;
    std::string pinName;
};


// ============================================================
// NET
// ============================================================

struct Net
{
    NetId name;

    std::vector<NetConnection> connections;

    void connect(const std::string& componentId, const std::string& pinName);
};


// ============================================================
// COMPONENT MODEL
// ============================================================

struct ComponentModel
{
    std::vector<Component> components;
    std::vector<Net> nets;

    void addComponent(const Component& component);

    void addNet(const Net& net);

    Component* findComponent(const std::string& id);

    const Component* findComponent(const std::string& id) const;

    Net* findNet(const NetId& name);

    const Net* findNet(const NetId& name) const;
};
