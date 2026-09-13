#pragma once

#include "routing_region.hpp"

class SpatialHierarchy
{
  public:
    SpatialHierarchy(RegionBounds bounds, int maxDepth);

    RoutingRegion& root();
    const RoutingRegion& root() const;

    int maxDepth() const;

    bool contains(Point p) const;

    RoutingRegion* touch(Point p);

    RoutingRegion* findLeaf(Point p);
    const RoutingRegion* findLeaf(Point p) const;

    bool markDirty(Point p);

    void clearDirty();

  private:
    RoutingRegion root_;
    int maxDepth_{};
};
