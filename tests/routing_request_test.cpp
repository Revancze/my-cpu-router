#include "routing_request.hpp"

#include <cassert>
#include <iostream>
#include <string>

int main()
{
    RouteRequest autoRequest;

    autoRequest.source =
        PinRef{"P1", "D"};

    autoRequest.target =
        PinRef{"N1", "D"};

    assert(autoRequest.source.componentId == "P1");
    assert(autoRequest.source.pinName == "D");

    assert(autoRequest.target.componentId == "N1");
    assert(autoRequest.target.pinName == "D");

    assert(autoRequest.mode == RoutingMode::AUTO);
    assert(autoRequest.waypoints.empty());

    RouteRequest guidedRequest;

    guidedRequest.source =
        PinRef{"P2", "G"};

    guidedRequest.target =
        PinRef{"N2", "G"};

    guidedRequest.mode =
        RoutingMode::GUIDED;

    guidedRequest.waypoints =
    {
        Point{15, 20, 0},
        Point{18, 20, 0}
    };

    assert(guidedRequest.mode == RoutingMode::GUIDED);
    assert(guidedRequest.waypoints.size() == 2);

    assert(
        (guidedRequest.waypoints[0] ==
         Point{15, 20, 0}));

    assert(
        (guidedRequest.waypoints[1] ==
         Point{18, 20, 0}));

    assert(
        std::string{
            routingModeName(RoutingMode::AUTO)
        } == "AUTO");

    assert(
        std::string{
            routingModeName(RoutingMode::GUIDED)
        } == "GUIDED");

    assert(
        std::string{
            routingModeName(RoutingMode::MANUAL)
        } == "MANUAL");

    std::cout
        << "AUTO: "
        << autoRequest.source.componentId
        << "."
        << autoRequest.source.pinName
        << " -> "
        << autoRequest.target.componentId
        << "."
        << autoRequest.target.pinName
        << '\n';

    std::cout
        << "GUIDED: waypoints="
        << guidedRequest.waypoints.size()
        << '\n';

    std::cout
        << "Modes: "
        << routingModeName(RoutingMode::AUTO)
        << ", "
        << routingModeName(RoutingMode::GUIDED)
        << ", "
        << routingModeName(RoutingMode::MANUAL)
        << '\n';

    std::cout
        << "routing_request test: PASS\n";

    return 0;
}
