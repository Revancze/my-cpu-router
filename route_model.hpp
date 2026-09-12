#pragma once

#include "net_id.hpp"
#include "segment.hpp"

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

    NetId netName;

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
