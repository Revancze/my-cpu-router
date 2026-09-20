#pragma once

#include "geometry.hpp"
#include "net_id.hpp"

#include <optional>
#include <cstddef>
#include <string>
#include <unordered_map>
#include <vector>

class RoutingRegion;
class SpatialHierarchy;

enum class SpatialObjectKind
{
    Unknown,
    Pin,
    WireSegment,
    Via,
    ComponentBody,
    Obstacle,
    KeepOut,
    RoutingCorridor
};

struct SpatialCongestion
{
    std::size_t pins{};
    std::size_t wireSegments{};
    std::size_t vias{};
    std::size_t componentBodies{};
    std::size_t obstacles{};
    std::size_t keepOuts{};

    std::size_t total() const
    {
        return pins + wireSegments + vias + componentBodies + obstacles +
               keepOuts;
    }
};

struct SpatialObjectRecord
{
    std::string id;
    RegionBounds bounds;
    SpatialObjectKind kind{SpatialObjectKind::Unknown};
    std::optional<NetId> netId;
};

class SpatialObjectIndex
{
  public:
    SpatialObjectIndex() = default;


    explicit SpatialObjectIndex(SpatialHierarchy& hierarchy);

    bool insert(const std::string& id,
                RegionBounds bounds,
                SpatialObjectKind kind = SpatialObjectKind::Unknown,
                std::optional<NetId> netId = std::nullopt);

    bool remove(const std::string& id);

    SpatialObjectRecord* find(const std::string& id);

    const SpatialObjectRecord* find(const std::string& id) const;

    std::vector<std::string> queryInside(RegionBounds bounds) const;

    std::vector<std::string> queryIntersecting(RegionBounds bounds) const;

    std::vector<std::string> queryIntersecting(RegionBounds bounds,
                                               SpatialObjectKind kind) const;

    std::vector<std::string> queryNetOccupancy(RegionBounds bounds,
                                               const NetId& netId) const;

    std::vector<std::string> queryLayerOccupancy(RegionBounds bounds,
                                                 int layer) const;
    SpatialCongestion queryCongestion(RegionBounds bounds) const;

    const SpatialObjectRecord* findNearest(Point point,
                                           SpatialObjectKind kind) const;

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
