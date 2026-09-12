#include "pin_to_pin_router.hpp"

// ===========================================================
// PIN-TO-PIN ROUTING
// ===========================================================

PinToPinRouteResult routePinToPin(
    const ComponentModel& model,
    const RouteRequest& request,
    const Router& router)
{
    PinToPinRouteResult result;

    if (request.mode != RoutingMode::AUTO)
    {
        result.status = PinToPinRouteStatus::UNSUPPORTED_MODE;
        return result;
    }

    const Component* sourceComponent =
        model.findComponent(request.source.componentId);

    if (sourceComponent == nullptr)
    {
        result.status = PinToPinRouteStatus::SOURCE_COMPONENT_NOT_FOUND;
        return result;
    }

    const Pin* sourcePin = sourceComponent->findPin(request.source.pinName);

    if (sourcePin == nullptr)
    {
        result.status = PinToPinRouteStatus::SOURCE_PIN_NOT_FOUND;
        return result;
    }

    const Component* targetComponent =
        model.findComponent(request.target.componentId);

    if (targetComponent == nullptr)
    {
        result.status = PinToPinRouteStatus::TARGET_COMPONENT_NOT_FOUND;
        return result;
    }

    const Pin* targetPin = targetComponent->findPin(request.target.pinName);

    if (targetPin == nullptr)
    {
        result.status = PinToPinRouteStatus::TARGET_PIN_NOT_FOUND;
        return result;
    }
    result.path = router.findPath(sourcePin->position, targetPin->position);


    if (!result.path.found())
    {
        result.status = PinToPinRouteStatus::PATH_NOT_FOUND;
        return result;
    }

    result.status = PinToPinRouteStatus::OK;
    return result;
}
