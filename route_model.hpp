#pragma once

#include "segment.hpp"

#include <string>
#include <vector>

enum class NetType
{
    Signal,
    VDD,
    VSS
};

enum class FactorioWire
{
    None,
    Red,
    Green
};

struct Wire
{
    char name{};

    std::string netName;

    NetType netType{
        NetType::Signal
    };

    FactorioWire factorioWire{
        FactorioWire::None
    };

    Path path;

    std::vector<Segment> segments;
};

struct RouteModel
{
    int width{};
    int height{};
    int layers{};

    std::vector<Wire> wires;

    void addWire(const Wire& wire);

    const Wire* findWire(char name) const;
};