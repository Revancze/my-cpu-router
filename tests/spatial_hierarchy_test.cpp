#include "../spatial_hierarchy.hpp"

#include <cassert>
#include <iostream>

int main()
{
    const RegionBounds bounds{0, 0, 0, 4096, 4096, 16};

    SpatialHierarchy hierarchy(bounds, 4);

    assert(hierarchy.maxDepth() == 4);
    assert(hierarchy.root().depth() == 0);
    assert(hierarchy.root().isLeaf());

    assert(hierarchy.contains(Point{0, 0, 0}));
    assert(hierarchy.contains(Point{4095, 4095, 15}));

    assert(!hierarchy.contains(Point{4096, 0, 0}));
    assert(!hierarchy.contains(Point{0, 4096, 0}));
    assert(!hierarchy.contains(Point{0, 0, 16}));

    RoutingRegion* first = hierarchy.touch(Point{100, 100, 2});

    assert(first != nullptr);
    assert(first->depth() == 4);

    assert(!hierarchy.root().isLeaf());

    RoutingRegion* firstAgain = hierarchy.touch(Point{100, 100, 2});

    assert(firstAgain == first);

    RoutingRegion* second = hierarchy.touch(Point{3500, 3500, 7});

    assert(second != nullptr);
    assert(second->depth() == 4);
    assert(second != first);

    assert(!first->dirty());
    assert(!second->dirty());

    assert(hierarchy.markDirty(Point{100, 100, 2}));

    assert(hierarchy.root().dirty());
    assert(first->dirty());
    assert(!second->dirty());

    hierarchy.clearDirty();

    assert(!hierarchy.root().dirty());
    assert(!first->dirty());
    assert(!second->dirty());

    assert(!hierarchy.markDirty(Point{5000, 5000, 0}));

    SpatialHierarchy shallow(RegionBounds{0, 0, 0, 8, 8, 64}, 2);

    RoutingRegion* shallowLeaf = shallow.touch(Point{7, 7, 63});

    assert(shallowLeaf != nullptr);
    assert(shallowLeaf->depth() == 2);

    assert(shallow.contains(Point{7, 7, 63}));
    assert(!shallow.contains(Point{7, 7, 64}));

    SpatialHierarchy tiny(RegionBounds{0, 0, 0, 1, 100, 8}, 10);

    RoutingRegion* tinyLeaf = tiny.touch(Point{0, 50, 4});

    assert(tinyLeaf != nullptr);
    assert(tinyLeaf->depth() == 0);

    std::cout << "spatial_hierarchy_test passed\n";

    return 0;
}
