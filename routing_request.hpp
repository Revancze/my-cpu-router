#pragma once

#include "router.hpp"

#include <string>
#include <vector>

// ============================================================
// PIN REFERENCE
// ============================================================

struct PinRef
{
    std::string componentId;
    std::string pinName;
};

// ============================================================
// ROUTING MODE
// ============================================================

enum class RoutingMode
{
    AUTO,
    GUIDED,
    MANUAL
};

// ============================================================
// ROUTING MODE HELPERS
// ============================================================

const char* routingModeName(RoutingMode mode);

// ============================================================
// ROUTING REQUEST
// ============================================================

struct RouteRequest
{
    PinRef source;
    PinRef target;

    RoutingMode mode{RoutingMode::AUTO};

    std::vector<Point> waypoints;
};
