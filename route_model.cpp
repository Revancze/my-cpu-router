#include "route_model.hpp"

void RouteModel::addWire(const Wire& wire)
{
    wires.push_back(wire);
}

const Wire* RouteModel::findWire(char name) const
{
    for (const Wire& wire : wires)
    {
        if (wire.name == name)
            return &wire;
    }

    return nullptr;
}