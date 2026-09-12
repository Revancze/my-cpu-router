#pragma once

#include "geometry.hpp"

#include <array>
#include <cstddef>
#include <memory>

struct RegionBounds
{
    int minX{};
    int minY{};
    int minZ{};

    int maxX{};
    int maxY{};
    int maxZ{};

    bool contains(Point p) const;

    int width() const;
    int height() const;
    int layers() const;
};

class RoutingRegion
{
  public:
    RoutingRegion(RegionBounds bounds, int depth = 0);

    const RegionBounds& bounds() const;

    int depth() const;

    bool dirty() const;

    bool isLeaf() const;

    bool canSubdivide() const;

    bool subdivide();

    RoutingRegion* findLeaf(Point p);
    const RoutingRegion* findLeaf(Point p) const;

    bool markDirty(Point p);

    void clearDirty();

    RoutingRegion* child(std::size_t index);
    const RoutingRegion* child(std::size_t index) const;

  private:
    RegionBounds bounds_;
    int depth_{};
    bool dirty_{};

    std::array<std::unique_ptr<RoutingRegion>, 4> children_;
};
