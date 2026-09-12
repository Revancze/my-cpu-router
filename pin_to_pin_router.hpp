#pragma once

#include "component_model.hpp"
#include "router.hpp"
#include "routing_request.hpp"
#include <string_view>
// ============================================================
// PIN-TO-PIN ROUTE STATUS
// ============================================================

enum class PinToPinRouteStatus
{
    OK,
    UNSUPPORTED_MODE,
    SOURCE_COMPONENT_NOT_FOUND,
    SOURCE_PIN_NOT_FOUND,
    TARGET_COMPONENT_NOT_FOUND,
    TARGET_PIN_NOT_FOUND,
    PATH_NOT_FOUND
};

[[nodiscard]]
constexpr std::string_view pinToPinRouteStatusName(
    PinToPinRouteStatus status) noexcept
{
    using enum PinToPinRouteStatus;

    switch (status)
    {
    case OK:
        return "OK";

    case UNSUPPORTED_MODE:
        return "UNSUPPORTED_MODE";

    case SOURCE_COMPONENT_NOT_FOUND:
        return "SOURCE_COMPONENT_NOT_FOUND";

    case SOURCE_PIN_NOT_FOUND:
        return "SOURCE_PIN_NOT_FOUND";

    case TARGET_COMPONENT_NOT_FOUND:
        return "TARGET_COMPONENT_NOT_FOUND";

    case TARGET_PIN_NOT_FOUND:
        return "TARGET_PIN_NOT_FOUND";

    case PATH_NOT_FOUND:
        return "PATH_NOT_FOUND";
    }

    return "UNKNOWN";
}

// ============================================================
// PIN-TO-PIN ROUTE RESULT
// ============================================================

struct PinToPinRouteResult
{
    PinToPinRouteStatus status{PinToPinRouteStatus::PATH_NOT_FOUND};

    Path path;

    bool success() const
    {
        return status == PinToPinRouteStatus::OK;
    }
};

// ============================================================
// PIN-TO-PIN ROUTING
// ============================================================

PinToPinRouteResult routePinToPin(const ComponentModel& model,
                                  const RouteRequest& request,
                                  const Router& router);
