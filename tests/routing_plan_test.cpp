#include "routing_plan.hpp"

#include <cassert>
#include <iostream>

int main()
{
    RoutingPlan plan;

    assert(plan.empty());
    assert(plan.size() == 0);

    // --------------------------------------------------------
    // BASIC CORRIDOR STORAGE
    // --------------------------------------------------------

    RoutingCorridor highway;

    highway.id = "D1";
    highway.bounds = RegionBounds{0, 100, 0, 1000, 200, 4};
    highway.policy = RoutingPolicy::Preferred;
    highway.direction = RoutingDirection::Horizontal;
    highway.priority = 100;

    assert(plan.addCorridor(highway));

    assert(!plan.empty());
    assert(plan.size() == 1);

    const RoutingCorridor* found = plan.findCorridor("D1");

    assert(found != nullptr);
    assert(found->id == "D1");
    assert(found->policy == RoutingPolicy::Preferred);
    assert(found->direction == RoutingDirection::Horizontal);
    assert(found->priority == 100);

    assert(plan.findCorridor("D35") == nullptr);

    RoutingCorridor duplicate = highway;

    duplicate.priority = 200;

    assert(!plan.addCorridor(duplicate));
    assert(plan.size() == 1);

    // --------------------------------------------------------
    // UNCONSTRAINED SPACE
    // --------------------------------------------------------

    RoutingDecisionResult decision = plan.evaluate(Point{2000, 2000, 0});

    assert(decision.decision == RoutingDecision::Unconstrained);
    assert(decision.direction == RoutingDirection::Any);

    // --------------------------------------------------------
    // PREFERRED CORRIDOR
    // --------------------------------------------------------

    decision = plan.evaluate(Point{100, 150, 0});

    assert(decision.decision == RoutingDecision::Preferred);
    assert(decision.direction == RoutingDirection::Horizontal);

    // --------------------------------------------------------
    // FORBIDDEN OVERRIDES EVERYTHING
    // --------------------------------------------------------

    RoutingCorridor forbidden;

    forbidden.id = "BRNO_CLOSED";
    forbidden.bounds = RegionBounds{400, 120, 0, 500, 180, 4};
    forbidden.policy = RoutingPolicy::Forbidden;
    forbidden.direction = RoutingDirection::Any;
    forbidden.priority = 1;

    assert(plan.addCorridor(forbidden));

    decision = plan.evaluate(Point{450, 150, 0});

    assert(decision.decision == RoutingDecision::Forbidden);
    assert(decision.direction == RoutingDirection::Any);

    // --------------------------------------------------------
    // REQUIRED OVERRIDES PREFERRED REGARDLESS OF PRIORITY
    // --------------------------------------------------------

    RoutingPlan requiredPlan;

    RoutingCorridor preferred;

    preferred.id = "D1_PREFERRED";
    preferred.bounds = RegionBounds{0, 0, 0, 100, 100, 4};
    preferred.policy = RoutingPolicy::Preferred;
    preferred.direction = RoutingDirection::Horizontal;
    preferred.priority = 1000;

    RoutingCorridor required;

    required.id = "SERVICE_REQUIRED";
    required.bounds = RegionBounds{0, 0, 0, 100, 100, 4};
    required.policy = RoutingPolicy::Required;
    required.direction = RoutingDirection::Vertical;
    required.priority = 1;

    assert(requiredPlan.addCorridor(preferred));
    assert(requiredPlan.addCorridor(required));

    decision = requiredPlan.evaluate(Point{50, 50, 0});

    assert(decision.decision == RoutingDecision::Required);
    assert(decision.direction == RoutingDirection::Vertical);

    // --------------------------------------------------------
    // HIGHER PRIORITY WINS WITHIN SAME POLICY
    // --------------------------------------------------------

    RoutingPlan priorityPlan;

    RoutingCorridor lowPriority;

    lowPriority.id = "LOW";
    lowPriority.bounds = RegionBounds{0, 0, 0, 100, 100, 4};
    lowPriority.policy = RoutingPolicy::Preferred;
    lowPriority.direction = RoutingDirection::Vertical;
    lowPriority.priority = 10;

    RoutingCorridor highPriority;

    highPriority.id = "HIGH";
    highPriority.bounds = RegionBounds{0, 0, 0, 100, 100, 4};
    highPriority.policy = RoutingPolicy::Preferred;
    highPriority.direction = RoutingDirection::Horizontal;
    highPriority.priority = 20;

    assert(priorityPlan.addCorridor(lowPriority));
    assert(priorityPlan.addCorridor(highPriority));

    decision = priorityPlan.evaluate(Point{50, 50, 0});

    assert(decision.decision == RoutingDecision::Preferred);
    assert(decision.direction == RoutingDirection::Horizontal);

    // --------------------------------------------------------
    // EQUAL PRIORITY + INCOMPATIBLE DIRECTIONS = CONFLICT
    // --------------------------------------------------------

    RoutingPlan conflictPlan;

    RoutingCorridor horizontal;

    horizontal.id = "HORIZONTAL";
    horizontal.bounds = RegionBounds{0, 0, 0, 100, 100, 4};
    horizontal.policy = RoutingPolicy::Required;
    horizontal.direction = RoutingDirection::Horizontal;
    horizontal.priority = 100;

    RoutingCorridor vertical;

    vertical.id = "VERTICAL";
    vertical.bounds = RegionBounds{0, 0, 0, 100, 100, 4};
    vertical.policy = RoutingPolicy::Required;
    vertical.direction = RoutingDirection::Vertical;
    vertical.priority = 100;

    assert(conflictPlan.addCorridor(horizontal));
    assert(conflictPlan.addCorridor(vertical));

    decision = conflictPlan.evaluate(Point{50, 50, 0});

    assert(decision.decision == RoutingDecision::Conflict);
    assert(decision.direction == RoutingDirection::Any);

    // --------------------------------------------------------
    // ANY IS COMPATIBLE WITH A SPECIFIC DIRECTION
    // --------------------------------------------------------

    RoutingPlan compatiblePlan;

    RoutingCorridor unrestricted;

    unrestricted.id = "ANY";
    unrestricted.bounds = RegionBounds{0, 0, 0, 100, 100, 4};
    unrestricted.policy = RoutingPolicy::Preferred;
    unrestricted.direction = RoutingDirection::Any;
    unrestricted.priority = 50;

    RoutingCorridor horizontalPreferred;

    horizontalPreferred.id = "HORIZONTAL_PREFERRED";
    horizontalPreferred.bounds = RegionBounds{0, 0, 0, 100, 100, 4};
    horizontalPreferred.policy = RoutingPolicy::Preferred;
    horizontalPreferred.direction = RoutingDirection::Horizontal;
    horizontalPreferred.priority = 50;

    assert(compatiblePlan.addCorridor(unrestricted));
    assert(compatiblePlan.addCorridor(horizontalPreferred));

    decision = compatiblePlan.evaluate(Point{50, 50, 0});

    assert(decision.decision == RoutingDecision::Preferred);
    assert(decision.direction == RoutingDirection::Horizontal);

    std::cout << "RoutingPlan corridors: " << plan.size() << '\n';
    std::cout << "routing_plan decision test: PASS\n";

    return 0;
}
