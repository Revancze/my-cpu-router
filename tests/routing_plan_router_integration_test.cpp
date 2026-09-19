#include "router.hpp"
#include "routing_plan.hpp"

#include <cassert>
#include <iostream>

int main()
{
    // --------------------------------------------------------
    // FORBIDDEN CELLS FORCE A DETOUR
    // --------------------------------------------------------

    Router forbiddenRouter(5, 3, 1);

    RoutingPlan forbiddenPlan;

    RoutingCorridor forbidden;

    forbidden.id = "ROAD_CLOSED";
    forbidden.bounds = RegionBounds{2, 1, 0, 3, 2, 1};
    forbidden.policy = RoutingPolicy::Forbidden;

    assert(forbiddenPlan.addCorridor(forbidden));

    const Path detour =
        forbiddenRouter.findPath(Point{0, 1, 0}, Point{4, 1, 0}, forbiddenPlan);

    assert(detour.found());
    assert(detour.length() > 4);

    for (const Point p : detour.points)
    {
        assert(!(p == Point{2, 1, 0}));
    }

    // --------------------------------------------------------
    // CONFLICT IS TREATED AS HARD BLOCK
    // --------------------------------------------------------

    Router conflictRouter(5, 3, 1);

    RoutingPlan conflictPlan;

    RoutingCorridor horizontal;

    horizontal.id = "H";
    horizontal.bounds = RegionBounds{2, 0, 0, 3, 3, 1};
    horizontal.policy = RoutingPolicy::Required;
    horizontal.direction = RoutingDirection::Horizontal;
    horizontal.priority = 100;

    RoutingCorridor vertical = horizontal;

    vertical.id = "V";
    vertical.direction = RoutingDirection::Vertical;

    assert(conflictPlan.addCorridor(horizontal));
    assert(conflictPlan.addCorridor(vertical));

    const Path conflictPath =
        conflictRouter.findPath(Point{0, 1, 0}, Point{4, 1, 0}, conflictPlan);

    assert(!conflictPath.found());

    // --------------------------------------------------------
    // REQUIRED DIRECTION IS ENFORCED INSIDE THE CORRIDOR
    // --------------------------------------------------------

    Router requiredRouter(6, 3, 1);

    RoutingPlan requiredPlan;

    RoutingCorridor verticalHighway;

    verticalHighway.id = "VERTICAL_HIGHWAY";
    verticalHighway.bounds = RegionBounds{2, 0, 0, 4, 3, 1};
    verticalHighway.policy = RoutingPolicy::Required;
    verticalHighway.direction = RoutingDirection::Vertical;
    verticalHighway.priority = 100;

    assert(requiredPlan.addCorridor(verticalHighway));

    const Path requiredPath =
        requiredRouter.findPath(Point{0, 1, 0}, Point{5, 1, 0}, requiredPlan);

    assert(!requiredPath.found());

    // --------------------------------------------------------
    // REQUIRED ANY DOES NOT RESTRICT MOVEMENT
    // --------------------------------------------------------

    Router anyRouter(6, 3, 1);

    RoutingPlan anyPlan;

    RoutingCorridor anyHighway = verticalHighway;

    anyHighway.id = "ANY_HIGHWAY";
    anyHighway.direction = RoutingDirection::Any;

    assert(anyPlan.addCorridor(anyHighway));

    const Path anyPath =
        anyRouter.findPath(Point{0, 1, 0}, Point{5, 1, 0}, anyPlan);

    assert(anyPath.found());
    assert(anyPath.length() == 5);

    std::cout << "routing_plan_router_integration test: PASS\n";

    return 0;
}
