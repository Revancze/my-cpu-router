#include "pin_to_pin_router.hpp"
#include "transistor_model.hpp"

#include <cassert>
#include <iostream>
#include <string>

int main()
{
    ComponentModel model;

    model.addComponent(
        makeTransistor(
            "P1",
            TransistorType::PMOS,
            Point{5, 5, 0}));

    model.addComponent(
        makeTransistor(
            "N1",
            TransistorType::NMOS,
            Point{15, 5, 0}));

    const Component* pmos =
        model.findComponent("P1");

    const Component* nmos =
        model.findComponent("N1");

    assert(pmos != nullptr);
    assert(nmos != nullptr);

    const Pin* sourcePin =
        pmos->findPin("D");

    const Pin* targetPin =
        nmos->findPin("D");

    assert(sourcePin != nullptr);
    assert(targetPin != nullptr);

    Router router(
        30,
        20,
        2);

    RouteRequest request;

    request.source =
        PinRef{"P1", "D"};

    request.target =
        PinRef{"N1", "D"};

    request.mode =
        RoutingMode::AUTO;

    const PinToPinRouteResult result =
        routePinToPin(
            model,
            request,
            router);

    assert(result.success());
    assert(result.status == PinToPinRouteStatus::OK);
    assert(result.path.found());

    assert(
        result.path.points.front() ==
        sourcePin->position);

    assert(
        result.path.points.back() ==
        targetPin->position);

    assert(result.path.length() == 10);
    assert(result.path.turns == 0);
    assert(result.path.layerChanges == 0);

    RouteRequest missingSourceComponent =
        request;

    missingSourceComponent.source.componentId =
        "MISSING";

    assert(
        routePinToPin(
            model,
            missingSourceComponent,
            router).status ==
        PinToPinRouteStatus::SOURCE_COMPONENT_NOT_FOUND);

    RouteRequest missingSourcePin =
        request;

    missingSourcePin.source.pinName =
        "MISSING";

    assert(
        routePinToPin(
            model,
            missingSourcePin,
            router).status ==
        PinToPinRouteStatus::SOURCE_PIN_NOT_FOUND);

    RouteRequest missingTargetComponent =
        request;

    missingTargetComponent.target.componentId =
        "MISSING";

    assert(
        routePinToPin(
            model,
            missingTargetComponent,
            router).status ==
        PinToPinRouteStatus::TARGET_COMPONENT_NOT_FOUND);

    RouteRequest missingTargetPin =
        request;

    missingTargetPin.target.pinName =
        "MISSING";

    assert(
        routePinToPin(
            model,
            missingTargetPin,
            router).status ==
        PinToPinRouteStatus::TARGET_PIN_NOT_FOUND);

    RouteRequest guidedRequest =
        request;

    guidedRequest.mode =
        RoutingMode::GUIDED;

    assert(
        routePinToPin(
            model,
            guidedRequest,
            router).status ==
        PinToPinRouteStatus::UNSUPPORTED_MODE);

    Router blockedRouter(
        30,
        20,
        2);

    blockedRouter.addObstacle(
        targetPin->position);

    const PinToPinRouteResult blockedResult =
        routePinToPin(
            model,
            request,
            blockedRouter);

    assert(
        blockedResult.status ==
        PinToPinRouteStatus::PATH_NOT_FOUND);

    assert(!blockedResult.success());
    assert(!blockedResult.path.found());

    std::cout
        << "Route: "
        << request.source.componentId
        << "."
        << request.source.pinName
        << " -> "
        << request.target.componentId
        << "."
        << request.target.pinName
        << '\n';

    std::cout
        << "Start=("
        << result.path.points.front().x << ","
        << result.path.points.front().y << ","
        << result.path.points.front().z << ")\n";

    std::cout
        << "End=("
        << result.path.points.back().x << ","
        << result.path.points.back().y << ","
        << result.path.points.back().z << ")\n";

    std::cout
        << "Length="
        << result.path.length()
        << " status="
        << pinToPinRouteStatusName(result.status)
        << '\n';

    std::cout
        << "pin_to_pin_routing test: PASS\n";

    return 0;
}
