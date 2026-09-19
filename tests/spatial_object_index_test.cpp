#include "spatial_hierarchy.hpp"
#include "spatial_object_index.hpp"

#include <algorithm>
#include <cassert>
#include <iostream>
#include <string>
#include <vector>

namespace
{
bool containsId(
    const std::vector<std::string>& ids,
    const std::string& id)
{
    return std::find(ids.begin(), ids.end(), id) != ids.end();
}
} // namespace

int main()
{
    SpatialObjectIndex index;

    assert(index.empty());
    assert(index.size() == 0);

    const RegionBounds pinBounds{10, 10, 0, 11, 11, 1};

    const RegionBounds wireBounds{20, 10, 0, 30, 11, 1};

    const RegionBounds obstacleBounds{25, 5, 0, 35, 15, 1};

    assert(index.insert("pin:A", pinBounds));

    assert(index.insert("wire:DATA:0", wireBounds));

    assert(index.insert("obstacle:BLOCK_A", obstacleBounds));

    assert(index.size() == 3);
    assert(!index.empty());

    // Duplicate stable identity must be rejected.
    assert(!index.insert("pin:A", RegionBounds{100, 100, 0, 101, 101, 1}));

    const SpatialObjectRecord* pin = index.find("pin:A");

    assert(pin != nullptr);
    assert(pin->id == "pin:A");
    assert(pin->bounds.minX == 10);
    assert(pin->bounds.maxX == 11);

    assert(index.find("missing") == nullptr);

    // --------------------------------------------------------
    // OBJECTS FULLY INSIDE QUERY REGION
    // --------------------------------------------------------

    const std::vector<std::string> inside =
        index.queryInside(RegionBounds{0, 0, 0, 31, 12, 1});

    assert(containsId(inside, "pin:A"));
    assert(containsId(inside, "wire:DATA:0"));

    // obstacle extends beyond maxX=31 / maxY=12,
    // so it intersects but is not fully contained.
    assert(!containsId(inside, "obstacle:BLOCK_A"));

    // --------------------------------------------------------
    // OBJECTS INTERSECTING QUERY REGION
    // --------------------------------------------------------

    const std::vector<std::string> intersecting =
        index.queryIntersecting(RegionBounds{28, 8, 0, 32, 12, 1});

    assert(!containsId(intersecting, "pin:A"));

    assert(containsId(intersecting, "wire:DATA:0"));

    assert(containsId(intersecting, "obstacle:BLOCK_A"));

    // --------------------------------------------------------
    // HALF-OPEN BOUNDS
    // --------------------------------------------------------

    const std::vector<std::string> touchingOnly =
        index.queryIntersecting(RegionBounds{11, 10, 0, 20, 11, 1});

    // pin ends at x=11 and wire begins at x=20.
    // Half-open bounds mean merely touching an edge
    // is not an intersection.
    assert(!containsId(touchingOnly, "pin:A"));

    assert(!containsId(touchingOnly, "wire:DATA:0"));

    // --------------------------------------------------------
    // REMOVE
    // --------------------------------------------------------

    assert(index.remove("wire:DATA:0"));
    assert(index.find("wire:DATA:0") == nullptr);
    assert(index.size() == 2);

    assert(!index.remove("wire:DATA:0"));
    assert(!index.remove("missing"));

    index.clear();

    assert(index.empty());
    assert(index.size() == 0);

    // --------------------------------------------------------
    // HIERARCHY-BACKED INDEX
    // --------------------------------------------------------

    SpatialHierarchy hierarchy(RegionBounds{0, 0, 0, 16, 16, 2}, 2);

    SpatialObjectIndex hierarchicalIndex(hierarchy);

    assert(hierarchicalIndex.insert("leaf:NW", RegionBounds{1, 1, 0, 2, 2, 1}));

    assert(hierarchicalIndex.insert("leaf:SE",
                                    RegionBounds{12, 12, 0, 13, 13, 1}));

    // This object crosses both x=8 and y=8.
    // It cannot belong exclusively to one child quadrant.
    assert(hierarchicalIndex.insert("cross:CENTER",
                                    RegionBounds{7, 7, 0, 9, 9, 1}));

    // Starts exactly at the half-open x=8 boundary.
    assert(
        hierarchicalIndex.insert("edge:EAST", RegionBounds{8, 2, 0, 9, 3, 1}));

    assert(hierarchicalIndex.size() == 4);

    // A hierarchy-backed index must not accept an object
    // outside its routing universe.
    assert(
        !hierarchicalIndex.insert("outside", RegionBounds{-1, 1, 0, 1, 2, 1}));

    assert(hierarchicalIndex.size() == 4);

    // --------------------------------------------------------
    // QUERY NORTH-WEST QUADRANT
    // --------------------------------------------------------

    const std::vector<std::string> northWest =
        hierarchicalIndex.queryIntersecting(RegionBounds{0, 0, 0, 8, 8, 1});

    assert(containsId(northWest, "leaf:NW"));

    // The cross-boundary object must still be discoverable
    // from either side of the quadrant boundary.
    assert(containsId(northWest, "cross:CENTER"));

    assert(!containsId(northWest, "leaf:SE"));

    // edge:EAST begins exactly at x=8, while this query ends
    // at x=8. Half-open bounds mean they do not intersect.
    assert(!containsId(northWest, "edge:EAST"));

    // --------------------------------------------------------
    // QUERY EAST SIDE
    // --------------------------------------------------------

    const std::vector<std::string> east =
        hierarchicalIndex.queryIntersecting(RegionBounds{8, 0, 0, 16, 8, 1});

    assert(containsId(east, "cross:CENTER"));

    assert(containsId(east, "edge:EAST"));

    assert(!containsId(east, "leaf:NW"));

    // --------------------------------------------------------
    // QUERY INSIDE NORTH-WEST QUADRANT
    // --------------------------------------------------------

    const std::vector<std::string> northWestInside =
        hierarchicalIndex.queryInside(RegionBounds{0, 0, 0, 8, 8, 1});

    assert(containsId(northWestInside, "leaf:NW"));

    // It intersects the quadrant, but is not fully inside it.
    assert(!containsId(northWestInside, "cross:CENTER"));

    assert(!containsId(northWestInside, "edge:EAST"));

    // --------------------------------------------------------
    // REMOVE FROM HIERARCHICAL INDEX
    // --------------------------------------------------------

    assert(hierarchicalIndex.remove("cross:CENTER"));

    const std::vector<std::string> afterRemove =
        hierarchicalIndex.queryIntersecting(RegionBounds{0, 0, 0, 16, 16, 1});

    assert(!containsId(afterRemove, "cross:CENTER"));

    assert(hierarchicalIndex.size() == 3);

    std::cout << "spatial_object_index test: PASS\n";

    return 0;
}
