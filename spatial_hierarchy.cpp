#include "spatial_hierarchy.hpp"

SpatialHierarchy::SpatialHierarchy(
    RegionBounds bounds,
    int maxDepth)
    : root_(bounds), maxDepth_(maxDepth < 0 ? 0 : maxDepth)
{
}

RoutingRegion& SpatialHierarchy::root()
{
    return root_;
}

const RoutingRegion& SpatialHierarchy::root() const
{
    return root_;
}

int SpatialHierarchy::maxDepth() const
{
    return maxDepth_;
}

bool SpatialHierarchy::contains(
    Point p) const
{
    return root_.bounds().contains(p);
}

RoutingRegion* SpatialHierarchy::touch(
    Point p)
{
    if (!contains(p))
        return nullptr;

    RoutingRegion* region = root_.findLeaf(p);

    while (region != nullptr && region->depth() < maxDepth_ &&
           region->canSubdivide())
    {
        if (!region->subdivide())
            break;

        region = region->findLeaf(p);
    }

    return region;
}

RoutingRegion* SpatialHierarchy::findLeaf(
    Point p)
{
    return root_.findLeaf(p);
}

const RoutingRegion* SpatialHierarchy::findLeaf(
    Point p) const
{
    return root_.findLeaf(p);
}

bool SpatialHierarchy::markDirty(
    Point p)
{
    if (touch(p) == nullptr)
        return false;

    return root_.markDirty(p);
}

void SpatialHierarchy::clearDirty()
{
    root_.clearDirty();
}
