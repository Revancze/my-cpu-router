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
    // --------------------------------------------------------
    // PREFERRED DIRECTION ADDS A SOFT COST
    // --------------------------------------------------------

    Router preferredCostRouter(3, 2, 1, 0, 0, 0);

    RoutingPlan preferredCostPlan;

    RoutingCorridor horizontalPreferred;

    horizontalPreferred.id = "HORIZONTAL_PREFERRED_COST";
    horizontalPreferred.bounds = RegionBounds{0, 0, 0, 3, 2, 1};
    horizontalPreferred.policy = RoutingPolicy::Preferred;
    horizontalPreferred.direction = RoutingDirection::Horizontal;
    horizontalPreferred.priority = 100;

    assert(preferredCostPlan.addCorridor(horizontalPreferred));

    const Path preferredCostPath =
        preferredCostRouter.findPath(Point{0, 0, 0},
                                     Point{2, 1, 0},
                                     preferredCostPlan);

    assert(preferredCostPath.found());
    assert(preferredCostPath.length() == 3);

    // 3 normal steps + 1 vertical step against
    // the horizontal preferred direction.
    assert(preferredCostPath.totalCost == 4);

    // --------------------------------------------------------
    // PREFERRED DIRECTION REMAINS SOFT
    // --------------------------------------------------------

    Router softPreferredRouter(1, 3, 1, 0, 0, 0);

    RoutingPlan softPreferredPlan;

    RoutingCorridor softHorizontalPreferred;

    softHorizontalPreferred.id = "SOFT_HORIZONTAL_PREFERRED";
    softHorizontalPreferred.bounds = RegionBounds{0, 0, 0, 1, 3, 1};
    softHorizontalPreferred.policy = RoutingPolicy::Preferred;
    softHorizontalPreferred.direction = RoutingDirection::Horizontal;
    softHorizontalPreferred.priority = 100;

    assert(softPreferredPlan.addCorridor(softHorizontalPreferred));

    const Path softPreferredPath =
        softPreferredRouter.findPath(Point{0, 0, 0},
                                     Point{0, 2, 0},
                                     softPreferredPlan);

    assert(softPreferredPath.found());
    assert(softPreferredPath.length() == 2);

    // Vertical movement is against the horizontal preference,
    // but Preferred must never block a legal route.
    assert(softPreferredPath.totalCost == 4);

    // --------------------------------------------------------
    // PREFERRED ANY DOES NOT ADD COST
    // --------------------------------------------------------

    Router preferredAnyRouter(3, 2, 1, 0, 0, 0);

    RoutingPlan preferredAnyPlan;

    RoutingCorridor preferredAny;

    preferredAny.id = "PREFERRED_ANY";
    preferredAny.bounds = RegionBounds{0, 0, 0, 3, 2, 1};
    preferredAny.policy = RoutingPolicy::Preferred;
    preferredAny.direction = RoutingDirection::Any;
    preferredAny.priority = 100;

    assert(preferredAnyPlan.addCorridor(preferredAny));

    const Path preferredAnyPath = preferredAnyRouter.findPath(Point{0, 0, 0},
                                                              Point{2, 1, 0},
                                                              preferredAnyPlan);

    assert(preferredAnyPath.found());
    assert(preferredAnyPath.length() == 3);
    assert(preferredAnyPath.totalCost == 3);

    // --------------------------------------------------------
    // PREFERRED COST CAN CHANGE THE SELECTED ROUTE
    // --------------------------------------------------------

    Router preferredSelectionRouter(5, 3, 1, 0, 0, 0, 5);

    const Path baselinePath =
        preferredSelectionRouter.findPath(Point{0, 1, 0}, Point{4, 1, 0});

    assert(baselinePath.found());
    assert(baselinePath.length() == 4);
    assert(baselinePath.totalCost == 4);

    RoutingPlan preferredSelectionPlan;

    RoutingCorridor verticalPreferred;

    verticalPreferred.id = "VERTICAL_PREFERRED_SELECTION";
    verticalPreferred.bounds = RegionBounds{1, 1, 0, 4, 2, 1};
    verticalPreferred.policy = RoutingPolicy::Preferred;
    verticalPreferred.direction = RoutingDirection::Vertical;
    verticalPreferred.priority = 100;

    assert(preferredSelectionPlan.addCorridor(verticalPreferred));

    const Path selectedByCostPath =
        preferredSelectionRouter.findPath(Point{0, 1, 0},
                                          Point{4, 1, 0},
                                          preferredSelectionPlan);

    assert(selectedByCostPath.found());

    // The direct route is only 4 steps, but crossing the
    // vertical-preferred corridor horizontally would cost more.
    // Dijkstra therefore chooses a 6-step detour.
    assert(selectedByCostPath.length() == 6);
    assert(selectedByCostPath.totalCost == 6);

    // --------------------------------------------------------
    // NEGATIVE PREFERRED PENALTY IS CLAMPED TO ZERO
    // --------------------------------------------------------

    Router negativePreferredRouter(3, 2, 1, 0, 0, 0, -5);

    const Path negativePreferredPath =
        negativePreferredRouter.findPath(Point{0, 0, 0},
                                         Point{2, 1, 0},
                                         preferredCostPlan);

    assert(negativePreferredPath.found());
    assert(negativePreferredPath.totalCost == 3);

    // --------------------------------------------------------
    // LAYER CHANGE BREAKS PLANAR TURN CONTINUITY
    // --------------------------------------------------------

    Router layerTurnRouter(2, 2, 2);

    layerTurnRouter.addObstacle(Point{0, 1, 0});
    layerTurnRouter.addObstacle(Point{0, 0, 1});
    layerTurnRouter.addObstacle(Point{1, 1, 0});

    const Path layerTurnPath =
        layerTurnRouter.findPath(Point{0, 0, 0}, Point{1, 1, 1});

    assert(layerTurnPath.found());
    assert(layerTurnPath.length() == 3);
    assert(layerTurnPath.layerChanges == 1);

    // Forced route:
    // (0,0,0) -> (1,0,0) -> (1,0,1) -> (1,1,1)
    //
    // The two planar moves are separated by a layer change.
    // Search cost therefore does not apply a planar turn penalty,
    // and the reported turn count must agree.
    assert(layerTurnPath.totalCost == 6);
    assert(layerTurnPath.turns == 0);
    std::cout << "routing_plan_router_integration test: PASS\n";

    return 0;
}
