#include "spatial_object_index.hpp"

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
} // namespace

bool SpatialObjectIndex::insert(
    const std::string& id,
    RegionBounds bounds)
{
    if (find(id) != nullptr)
        return false;

    records_.push_back(SpatialObjectRecord{id, bounds});

    return true;
}

bool SpatialObjectIndex::remove(
    const std::string& id)
{
    const auto it = std::find_if(records_.begin(),
                                 records_.end(),
                                 [&id](const SpatialObjectRecord& record)
                                 {
                                     return record.id == id;
                                 });

    if (it == records_.end())
        return false;

    records_.erase(it);

    return true;
}

SpatialObjectRecord* SpatialObjectIndex::find(
    const std::string& id)
{
    const auto it = std::find_if(records_.begin(),
                                 records_.end(),
                                 [&id](const SpatialObjectRecord& record)
                                 {
                                     return record.id == id;
                                 });

    if (it == records_.end())
        return nullptr;

    return &(*it);
}

const SpatialObjectRecord* SpatialObjectIndex::find(
    const std::string& id) const
{
    const auto it = std::find_if(records_.begin(),
                                 records_.end(),
                                 [&id](const SpatialObjectRecord& record)
                                 {
                                     return record.id == id;
                                 });

    if (it == records_.end())
        return nullptr;

    return &(*it);
}

std::vector<std::string> SpatialObjectIndex::queryInside(
    RegionBounds bounds) const
{
    std::vector<std::string> result;

    for (const SpatialObjectRecord& record : records_)
    {
        if (containsBounds(bounds, record.bounds))
        {
            result.push_back(record.id);
        }
    }

    return result;
}

std::vector<std::string> SpatialObjectIndex::queryIntersecting(
    RegionBounds bounds) const
{
    std::vector<std::string> result;

    for (const SpatialObjectRecord& record : records_)
    {
        if (intersectsBounds(bounds, record.bounds))
        {
            result.push_back(record.id);
        }
    }

    return result;
}

void SpatialObjectIndex::clear()
{
    records_.clear();
}

bool SpatialObjectIndex::empty() const
{
    return records_.empty();
}

std::size_t SpatialObjectIndex::size() const
{
    return records_.size();
}
