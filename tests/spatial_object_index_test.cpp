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

    std::cout << "spatial_object_index test: PASS\n";

    return 0;
}
