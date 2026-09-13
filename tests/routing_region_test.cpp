#include "../routing_region.hpp"

#include <cassert>
#include <iostream>

int main()
{
    const RegionBounds galaxyBounds{0, 0, 0, 100, 100, 4};

    RoutingRegion galaxy(galaxyBounds);

    assert(galaxy.depth() == 0);
    assert(galaxy.isLeaf());
    assert(!galaxy.dirty());

    assert(galaxyBounds.contains(Point{0, 0, 0}));
    assert(galaxyBounds.contains(Point{99, 99, 3}));

    assert(!galaxyBounds.contains(Point{100, 99, 3}));
    assert(!galaxyBounds.contains(Point{99, 100, 3}));
    assert(!galaxyBounds.contains(Point{99, 99, 4}));

    assert(galaxy.subdivide());
    assert(!galaxy.isLeaf());
    assert(galaxy.child(0) != nullptr);
    assert(galaxy.child(1) != nullptr);
    assert(galaxy.child(2) != nullptr);
    assert(galaxy.child(3) != nullptr);
    assert(galaxy.child(4) == nullptr);

    assert(galaxy.child(0)->bounds().contains(Point{49, 49, 3}));
    assert(!galaxy.child(0)->bounds().contains(Point{50, 49, 3}));

    assert(galaxy.child(1)->bounds().contains(Point{50, 49, 3}));
    assert(galaxy.child(2)->bounds().contains(Point{49, 50, 3}));
    assert(galaxy.child(3)->bounds().contains(Point{50, 50, 3}));

    assert(!galaxy.subdivide());

    RoutingRegion* firstLeaf = galaxy.findLeaf(Point{10, 10, 0});

    RoutingRegion* secondLeaf = galaxy.findLeaf(Point{75, 75, 0});

    assert(firstLeaf != nullptr);
    assert(secondLeaf != nullptr);
    assert(firstLeaf != secondLeaf);

    assert(firstLeaf->depth() == 1);
    assert(secondLeaf->depth() == 1);

    assert(!firstLeaf->dirty());
    assert(!secondLeaf->dirty());

    assert(galaxy.markDirty(Point{10, 10, 0}));

    assert(galaxy.dirty());
    assert(firstLeaf->dirty());
    assert(!secondLeaf->dirty());

    assert(!galaxy.markDirty(Point{200, 200, 0}));

    galaxy.clearDirty();

    assert(!galaxy.dirty());
    assert(!firstLeaf->dirty());
    assert(!secondLeaf->dirty());

    assert(firstLeaf->subdivide());

    RoutingRegion* deepLeaf = galaxy.findLeaf(Point{10, 10, 0});

    assert(deepLeaf != nullptr);
    assert(deepLeaf->depth() == 2);

    assert(galaxy.markDirty(Point{10, 10, 0}));

    assert(galaxy.dirty());
    assert(firstLeaf->dirty());
    assert(deepLeaf->dirty());

    std::cout << "routing_region_test passed\n";

    return 0;
}
