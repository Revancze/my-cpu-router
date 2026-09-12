#include "component_model.hpp"


// ============================================================
// COMPONENT
// ============================================================

Pin* Component::findPin(
    const std::string& name)
{
    for (Pin& pin : pins)
    {
        if (pin.name == name)
        {
            return &pin;
        }
    }

    return nullptr;
}


const Pin* Component::findPin(
    const std::string& name) const
{
    for (const Pin& pin : pins)
    {
        if (pin.name == name)
        {
            return &pin;
        }
    }

    return nullptr;
}


// ============================================================
// NET
// ============================================================

void Net::connect(
    const std::string& componentId,
    const std::string& pinName)
{
    connections.push_back(
        NetConnection{
            componentId,
            pinName
        });
}


// ============================================================
// COMPONENT MODEL
// ============================================================

void ComponentModel::addComponent(
    const Component& component)
{
    components.push_back(
        component);
}


void ComponentModel::addNet(
    const Net& net)
{
    nets.push_back(
        net);
}


Component* ComponentModel::findComponent(
    const std::string& id)
{
    for (Component& component :
         components)
    {
        if (component.id == id)
        {
            return &component;
        }
    }

    return nullptr;
}


const Component* ComponentModel::findComponent(
    const std::string& id) const
{
    for (const Component& component :
         components)
    {
        if (component.id == id)
        {
            return &component;
        }
    }

    return nullptr;
}


Net* ComponentModel::findNet(
    const NetId& name)
{
    for (Net& net : nets)
    {
        if (net.name == name)
        {
            return &net;
        }
    }

    return nullptr;
}


const Net* ComponentModel::findNet(
    const NetId& name) const
{
    for (const Net& net : nets)
    {
        if (net.name == name)
        {
            return &net;
        }
    }

    return nullptr;
}
