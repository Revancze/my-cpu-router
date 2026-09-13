#include "routing_region.hpp"


RoutingRegion::RoutingRegion(
    RegionBounds bounds,
    int depth)
    : bounds_(bounds), depth_(depth)
{
}

const RegionBounds& RoutingRegion::bounds() const
{
    return bounds_;
}

int RoutingRegion::depth() const
{
    return depth_;
}

bool RoutingRegion::dirty() const
{
    return dirty_;
}

bool RoutingRegion::isLeaf() const
{
    return children_[0] == nullptr;
}

bool RoutingRegion::canSubdivide() const
{
    return bounds_.width() >= 2 && bounds_.height() >= 2;
}

bool RoutingRegion::subdivide()
{
    if (!isLeaf() || !canSubdivide())
        return false;

    const int midX = bounds_.minX + bounds_.width() / 2;
    const int midY = bounds_.minY + bounds_.height() / 2;

    const int nextDepth = depth_ + 1;

    children_[0] = std::make_unique<RoutingRegion>(RegionBounds{bounds_.minX,
                                                                bounds_.minY,
                                                                bounds_.minZ,
                                                                midX,
                                                                midY,
                                                                bounds_.maxZ},
                                                   nextDepth);

    children_[1] = std::make_unique<RoutingRegion>(RegionBounds{midX,
                                                                bounds_.minY,
                                                                bounds_.minZ,
                                                                bounds_.maxX,
                                                                midY,
                                                                bounds_.maxZ},
                                                   nextDepth);

    children_[2] = std::make_unique<RoutingRegion>(RegionBounds{bounds_.minX,
                                                                midY,
                                                                bounds_.minZ,
                                                                midX,
                                                                bounds_.maxY,
                                                                bounds_.maxZ},
                                                   nextDepth);

    children_[3] = std::make_unique<RoutingRegion>(RegionBounds{midX,
                                                                midY,
                                                                bounds_.minZ,
                                                                bounds_.maxX,
                                                                bounds_.maxY,
                                                                bounds_.maxZ},
                                                   nextDepth);

    return true;
}

RoutingRegion* RoutingRegion::findLeaf(
    Point p)
{
    if (!bounds_.contains(p))
        return nullptr;

    if (isLeaf())
        return this;

    for (auto& childRegion : children_)
    {
        if (childRegion != nullptr && childRegion->bounds().contains(p))
        {
            return childRegion->findLeaf(p);
        }
    }

    return nullptr;
}

const RoutingRegion* RoutingRegion::findLeaf(
    Point p) const
{
    if (!bounds_.contains(p))
        return nullptr;

    if (isLeaf())
        return this;

    for (const auto& childRegion : children_)
    {
        if (childRegion != nullptr && childRegion->bounds().contains(p))
        {
            return childRegion->findLeaf(p);
        }
    }

    return nullptr;
}

bool RoutingRegion::markDirty(
    Point p)
{
    if (!bounds_.contains(p))
        return false;

    dirty_ = true;

    if (isLeaf())
        return true;

    for (auto& childRegion : children_)
    {
        if (childRegion != nullptr && childRegion->bounds().contains(p))
        {
            return childRegion->markDirty(p);
        }
    }

    return false;
}

void RoutingRegion::clearDirty()
{
    dirty_ = false;

    for (auto& childRegion : children_)
    {
        if (childRegion != nullptr)
            childRegion->clearDirty();
    }
}

RoutingRegion* RoutingRegion::child(
    std::size_t index)
{
    if (index >= children_.size())
        return nullptr;

    return children_[index].get();
}

const RoutingRegion* RoutingRegion::child(
    std::size_t index) const
{
    if (index >= children_.size())
        return nullptr;

    return children_[index].get();
}
