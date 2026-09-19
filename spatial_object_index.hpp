#pragma once

#include "geometry.hpp"

#include <cstddef>
#include <string>
#include <unordered_map>
#include <vector>

class RoutingRegion;
class SpatialHierarchy;

struct SpatialObjectRecord
{
    std::string id;
    RegionBounds bounds;
};

class SpatialObjectIndex
{
  public:
    SpatialObjectIndex() = default;

    explicit SpatialObjectIndex(SpatialHierarchy& hierarchy);

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
    SpatialHierarchy* hierarchy_{nullptr};

    std::unordered_map<std::string, std::size_t> recordIndex_;

    std::unordered_map<std::string, const RoutingRegion*> objectRegions_;

    std::vector<SpatialObjectRecord> records_;

    std::unordered_map<const RoutingRegion*, std::vector<std::string>>
        regionObjects_;
};
