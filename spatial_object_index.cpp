#include "spatial_object_index.hpp"

#include "routing_region.hpp"
#include "spatial_hierarchy.hpp"

#include <algorithm>

namespace
{
bool containsBounds(
    const RegionBounds& outer,
    const RegionBounds& inner)
{
    return inner.minX >= outer.minX && inner.minY >= outer.minY &&
           inner.minZ >= outer.minZ && inner.maxX <= outer.maxX &&
           inner.maxY <= outer.maxY && inner.maxZ <= outer.maxZ;
}

bool intersectsBounds(
    const RegionBounds& a,
    const RegionBounds& b)
{
    return a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY &&
           a.maxY > b.minY && a.minZ < b.maxZ && a.maxZ > b.minZ;
}

RoutingRegion* findStorageRegion(
    SpatialHierarchy& hierarchy,
    const RegionBounds& bounds)
{
    RoutingRegion* region = &hierarchy.root();

    if (!containsBounds(region->bounds(), bounds))
        return nullptr;

    while (region->depth() < hierarchy.maxDepth() && region->canSubdivide())
    {
        if (region->isLeaf())
        {
            if (!region->subdivide())
                break;
        }

        RoutingRegion* containingChild = nullptr;

        for (std::size_t i = 0; i < 4; ++i)
        {
            RoutingRegion* child = region->child(i);

            if (child != nullptr && containsBounds(child->bounds(), bounds))
            {
                containingChild = child;
                break;
            }
        }

        // The object crosses a child boundary.
        // Store it in the current parent region.
        if (containingChild == nullptr)
            break;

        region = containingChild;
    }

    return region;
}

void collectCandidateIds(
    const RoutingRegion& region,
    const RegionBounds& queryBounds,
    const std::unordered_map<const RoutingRegion*, std::vector<std::string>>&
        regionObjects,
    std::vector<std::string>& result)
{
    if (!intersectsBounds(region.bounds(), queryBounds))
    {
        return;
    }

    const auto bucket = regionObjects.find(&region);

    if (bucket != regionObjects.end())
    {
        result.insert(result.end(),
                      bucket->second.begin(),
                      bucket->second.end());
    }

    for (std::size_t i = 0; i < 4; ++i)
    {
        const RoutingRegion* child = region.child(i);

        if (child != nullptr)
        {
            collectCandidateIds(*child, queryBounds, regionObjects, result);
        }
    }
}
} // namespace

SpatialObjectIndex::SpatialObjectIndex(
    SpatialHierarchy& hierarchy)
    : hierarchy_(&hierarchy)
{
}

bool SpatialObjectIndex::insert(
    const std::string& id,
    RegionBounds bounds,
    SpatialObjectKind kind)
{
    if (recordIndex_.find(id) != recordIndex_.end())
        return false;

    RoutingRegion* storageRegion = nullptr;

    if (hierarchy_ != nullptr)
    {
        storageRegion = findStorageRegion(*hierarchy_, bounds);

        if (storageRegion == nullptr)
            return false;
    }

    const std::size_t index = records_.size();

    records_.push_back(SpatialObjectRecord{id, bounds, kind});

    recordIndex_[id] = index;

    if (storageRegion != nullptr)
    {
        regionObjects_[storageRegion].push_back(id);
        objectRegions_[id] = storageRegion;
    }

    return true;
}

bool SpatialObjectIndex::remove(
    const std::string& id)
{
    const auto indexEntry = recordIndex_.find(id);

    if (indexEntry == recordIndex_.end())
        return false;

    const std::size_t removedIndex = indexEntry->second;

    const auto regionEntry = objectRegions_.find(id);

    if (regionEntry != objectRegions_.end())
    {
        const RoutingRegion* region = regionEntry->second;

        const auto bucketEntry = regionObjects_.find(region);

        if (bucketEntry != regionObjects_.end())
        {
            std::vector<std::string>& ids = bucketEntry->second;

            ids.erase(std::remove(ids.begin(), ids.end(), id), ids.end());

            if (ids.empty())
            {
                regionObjects_.erase(bucketEntry);
            }
        }

        objectRegions_.erase(regionEntry);
    }

    records_.erase(records_.begin() +
                   static_cast<std::ptrdiff_t>(removedIndex));

    recordIndex_.erase(indexEntry);

    for (std::size_t i = removedIndex; i < records_.size(); ++i)
    {
        recordIndex_[records_[i].id] = i;
    }

    return true;
}

SpatialObjectRecord* SpatialObjectIndex::find(
    const std::string& id)
{
    const auto it = recordIndex_.find(id);

    if (it == recordIndex_.end())
        return nullptr;

    return &records_[it->second];
}

const SpatialObjectRecord* SpatialObjectIndex::find(
    const std::string& id) const
{
    const auto it = recordIndex_.find(id);

    if (it == recordIndex_.end())
        return nullptr;

    return &records_[it->second];
}

std::vector<std::string> SpatialObjectIndex::queryInside(
    RegionBounds bounds) const
{
    std::vector<std::string> result;

    if (hierarchy_ == nullptr)
    {
        for (const SpatialObjectRecord& record : records_)
        {
            if (containsBounds(bounds, record.bounds))
            {
                result.push_back(record.id);
            }
        }

        return result;
    }

    std::vector<std::string> candidates;

    collectCandidateIds(hierarchy_->root(), bounds, regionObjects_, candidates);

    for (const std::string& id : candidates)
    {
        const SpatialObjectRecord* record = find(id);

        if (record != nullptr && containsBounds(bounds, record->bounds))
        {
            result.push_back(id);
        }
    }

    return result;
}

std::vector<std::string> SpatialObjectIndex::queryIntersecting(
    RegionBounds bounds) const
{
    std::vector<std::string> result;

    if (hierarchy_ == nullptr)
    {
        for (const SpatialObjectRecord& record : records_)
        {
            if (intersectsBounds(bounds, record.bounds))
            {
                result.push_back(record.id);
            }
        }

        return result;
    }

    std::vector<std::string> candidates;

    collectCandidateIds(hierarchy_->root(), bounds, regionObjects_, candidates);

    for (const std::string& id : candidates)
    {
        const SpatialObjectRecord* record = find(id);

        if (record != nullptr && intersectsBounds(bounds, record->bounds))
        {
            result.push_back(id);
        }
    }

    return result;
}

std::vector<std::string> SpatialObjectIndex::queryIntersecting(
    RegionBounds bounds,
    SpatialObjectKind kind) const
{
    std::vector<std::string> result;

    const std::vector<std::string> candidates = queryIntersecting(bounds);

    for (const std::string& id : candidates)
    {
        const SpatialObjectRecord* record = find(id);

        if (record != nullptr && record->kind == kind)
        {
            result.push_back(id);
        }
    }

    return result;
}

void SpatialObjectIndex::clear()
{
    records_.clear();
    recordIndex_.clear();
    regionObjects_.clear();
    objectRegions_.clear();
}

bool SpatialObjectIndex::empty() const
{
    return records_.empty();
}

std::size_t SpatialObjectIndex::size() const
{
    return records_.size();
}
