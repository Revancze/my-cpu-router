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

    assert(index.insert("pin:A", pinBounds, SpatialObjectKind::Pin));

    assert(index.insert("wire:DATA:0",
                        wireBounds,
                        SpatialObjectKind::WireSegment));

    assert(index.insert("obstacle:BLOCK_A",
                        obstacleBounds,
                        SpatialObjectKind::Obstacle));

    assert(index.size() == 3);
    assert(!index.empty());

    // Duplicate stable identity must be rejected.
    assert(!index.insert("pin:A", RegionBounds{100, 100, 0, 101, 101, 1}));

    const SpatialObjectRecord* pin = index.find("pin:A");

    assert(pin != nullptr);
    assert(pin->id == "pin:A");
    assert(pin->bounds.minX == 10);
    assert(pin->bounds.maxX == 11);
    assert(pin->kind == SpatialObjectKind::Pin);

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
    // OBJECT KIND FILTERING
    // --------------------------------------------------------

    const std::vector<std::string> obstacles =
        index.queryIntersecting(RegionBounds{20, 0, 0, 40, 20, 1},
                                SpatialObjectKind::Obstacle);

    assert(containsId(obstacles, "obstacle:BLOCK_A"));

    assert(!containsId(obstacles, "wire:DATA:0"));

    assert(!containsId(obstacles, "pin:A"));

    // --------------------------------------------------------
    // NEAREST OBJECT BY KIND
    // --------------------------------------------------------

    SpatialObjectIndex nearestIndex;

    // Closer object, but wrong kind: must be ignored.
    assert(nearestIndex.insert("pin:NEAR",
                               RegionBounds{1, 0, 0, 2, 1, 1},
                               SpatialObjectKind::Pin));

    // Manhattan distance from (0,0,0) = 5.
    assert(nearestIndex.insert("obstacle:AXIS",
                               RegionBounds{5, 0, 0, 6, 1, 1},
                               SpatialObjectKind::Obstacle));

    // Manhattan distance from (0,0,0) = 6.
    // Euclidean distance would be smaller than AXIS,
    // so this proves that nearest uses grid Manhattan distance.
    assert(nearestIndex.insert("obstacle:DIAGONAL",
                               RegionBounds{3, 3, 0, 4, 4, 1},
                               SpatialObjectKind::Obstacle));

    const SpatialObjectRecord* nearestObstacle =
        nearestIndex.findNearest(Point{0, 0, 0}, SpatialObjectKind::Obstacle);

    assert(nearestObstacle != nullptr);
    assert(nearestObstacle->id == "obstacle:AXIS");

    // A point inside an object has distance zero.
    const SpatialObjectRecord* containingObstacle =
        nearestIndex.findNearest(Point{5, 0, 0}, SpatialObjectKind::Obstacle);

    assert(containingObstacle != nullptr);
    assert(containingObstacle->id == "obstacle:AXIS");

    // No object of the requested kind.
    assert(nearestIndex.findNearest(Point{0, 0, 0}, SpatialObjectKind::Via) ==
           nullptr);

    // --------------------------------------------------------
    // DETERMINISTIC TIE BREAK
    // --------------------------------------------------------

    SpatialObjectIndex tieIndex;

    assert(tieIndex.insert("obstacle:Z",
                           RegionBounds{1, 0, 0, 2, 1, 1},
                           SpatialObjectKind::Obstacle));

    assert(tieIndex.insert("obstacle:A",
                           RegionBounds{0, 1, 0, 1, 2, 1},
                           SpatialObjectKind::Obstacle));

    const SpatialObjectRecord* tied =
        tieIndex.findNearest(Point{0, 0, 0}, SpatialObjectKind::Obstacle);

    assert(tied != nullptr);

    // Equal distance must have deterministic behavior
    // independent of insertion or hierarchy traversal order.
    assert(tied->id == "obstacle:A");

    // --------------------------------------------------------
    // HIERARCHY-BACKED NEAREST OBJECT
    // --------------------------------------------------------

    SpatialHierarchy nearestHierarchy(RegionBounds{0, 0, 0, 16, 16, 2}, 2);

    SpatialObjectIndex hierarchicalNearest(nearestHierarchy);

    assert(hierarchicalNearest.insert("pin:CLOSE",
                                      RegionBounds{1, 1, 0, 2, 2, 1},
                                      SpatialObjectKind::Pin));

    assert(hierarchicalNearest.insert("obstacle:NEAR",
                                      RegionBounds{2, 2, 0, 3, 3, 1},
                                      SpatialObjectKind::Obstacle));

    assert(hierarchicalNearest.insert("obstacle:FAR",
                                      RegionBounds{12, 12, 0, 13, 13, 1},
                                      SpatialObjectKind::Obstacle));

    const SpatialObjectRecord* hierarchyNearest =
        hierarchicalNearest.findNearest(Point{0, 0, 0},
                                        SpatialObjectKind::Obstacle);

    assert(hierarchyNearest != nullptr);
    assert(hierarchyNearest->id == "obstacle:NEAR");

    // --------------------------------------------------------
    // HIERARCHY NEAREST TIE ACROSS BRANCHES
    // --------------------------------------------------------

    SpatialHierarchy tieHierarchy(RegionBounds{0, 0, 0, 16, 16, 2}, 2);

    SpatialObjectIndex hierarchicalTie(tieHierarchy);

    // Insert Z first in the western branch.
    // Distance from (7,7,0) = 1.
    assert(hierarchicalTie.insert("obstacle:Z",
                                  RegionBounds{6, 7, 0, 7, 8, 1},
                                  SpatialObjectKind::Obstacle));

    // Same distance, but in the eastern branch.
    // Lexicographically smaller ID must win even if another
    // hierarchy branch already produced the same best distance.
    assert(hierarchicalTie.insert("obstacle:A",
                                  RegionBounds{8, 7, 0, 9, 8, 1},
                                  SpatialObjectKind::Obstacle));

    const SpatialObjectRecord* hierarchyTieResult =
        hierarchicalTie.findNearest(Point{7, 7, 0},
                                    SpatialObjectKind::Obstacle);

    assert(hierarchyTieResult != nullptr);
    assert(hierarchyTieResult->id == "obstacle:A");

    // --------------------------------------------------------
    // HIERARCHY NEAREST PARENT-STORED OBJECT
    // --------------------------------------------------------

    SpatialHierarchy parentHierarchy(RegionBounds{0, 0, 0, 16, 16, 2}, 2);

    SpatialObjectIndex parentNearest(parentHierarchy);

    // Crosses the x=8 and y=8 child boundaries,
    // therefore it must remain stored in the parent region.
    assert(parentNearest.insert("obstacle:CROSS",
                                RegionBounds{7, 7, 0, 9, 9, 1},
                                SpatialObjectKind::Obstacle));

    // Stored deep in a child branch.
    assert(parentNearest.insert("obstacle:FAR",
                                RegionBounds{14, 14, 0, 15, 15, 1},
                                SpatialObjectKind::Obstacle));

    const SpatialObjectRecord* parentStoredNearest =
        parentNearest.findNearest(Point{8, 8, 0}, SpatialObjectKind::Obstacle);

    assert(parentStoredNearest != nullptr);
    assert(parentStoredNearest->id == "obstacle:CROSS");

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

    const SpatialObjectRecord* legacyObject = hierarchicalIndex.find("leaf:NW");

    assert(legacyObject != nullptr);

    assert(legacyObject->kind == SpatialObjectKind::Unknown);

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
