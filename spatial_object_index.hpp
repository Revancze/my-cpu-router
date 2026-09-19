#pragma once

#include "geometry.hpp"

#include <cstddef>
#include <string>
#include <vector>

struct SpatialObjectRecord
{
    std::string id;
    RegionBounds bounds;
};

class SpatialObjectIndex
{
  public:
    bool insert(const std::string& id, RegionBounds bounds);

    bool remove(const std::string& id);

    SpatialObjectRecord* find(const std::string& id);

    const SpatialObjectRecord* find(const std::string& id) const;

    std::vector<std::string> queryInside(RegionBounds bounds) const;

    std::vector<std::string> queryIntersecting(RegionBounds bounds) const;

    void clear();

    bool empty() const;

    std::size_t size() const;

  private:
    std::vector<SpatialObjectRecord> records_;
};
