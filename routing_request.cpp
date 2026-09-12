#include "routing_request.hpp"

// ============================================================
// ROUTING MODE HELPERS
// ============================================================

const char* routingModeName(
    RoutingMode mode)
{
    switch (mode)
    {
    case RoutingMode::AUTO:
        return "AUTO";

    case RoutingMode::GUIDED:
        return "GUIDED";

    case RoutingMode::MANUAL:
        return "MANUAL";
    }

    return "UNKNOWN";
}
