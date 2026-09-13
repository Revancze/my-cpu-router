#include "routing_plan.hpp"

#include <cassert>
#include <iostream>

int main()
{
    RoutingPlan plan;

    assert(plan.empty());
    assert(plan.size() == 0);

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

    assert(found->bounds.minX == 0);
    assert(found->bounds.minY == 100);
    assert(found->bounds.minZ == 0);

    assert(found->bounds.maxX == 1000);
    assert(found->bounds.maxY == 200);
    assert(found->bounds.maxZ == 4);

    assert(found->policy == RoutingPolicy::Preferred);
    assert(found->direction == RoutingDirection::Horizontal);
    assert(found->priority == 100);

    assert(plan.findCorridor("D35") == nullptr);

    RoutingCorridor duplicate = highway;

    duplicate.priority = 200;

    assert(!plan.addCorridor(duplicate));
    assert(plan.size() == 1);

    RoutingCorridor forbidden;

    forbidden.id = "BRNO_CLOSED";

    forbidden.bounds = RegionBounds{400, 120, 0, 500, 180, 4};

    forbidden.policy = RoutingPolicy::Forbidden;
    forbidden.direction = RoutingDirection::Any;
    forbidden.priority = 1000;

    assert(plan.addCorridor(forbidden));
    assert(plan.size() == 2);

    std::cout << "RoutingPlan corridors: " << plan.size() << '\n';
    std::cout << "routing_plan test: PASS\n";

    return 0;
}
