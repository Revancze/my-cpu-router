#pragma once

#include "geometry.hpp"

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

// ============================================================
// ROUTING POLICY
// ============================================================

enum class RoutingPolicy
{
    Preferred,
    Required,
    Forbidden
};

// ============================================================
// ROUTING DIRECTION
// ============================================================

enum class RoutingDirection
{
    Any,
    Horizontal,
    Vertical
};

// ============================================================
// ROUTING CORRIDOR
// ============================================================

struct RoutingCorridor
{
    std::string id;

    RegionBounds bounds;

    RoutingPolicy policy{RoutingPolicy::Preferred};
    RoutingDirection direction{RoutingDirection::Any};

    int priority{};
};

// ============================================================
// ROUTING PLAN
// ============================================================

class RoutingPlan
{
  public:
    bool addCorridor(
        const RoutingCorridor& corridor)
    {
        if (corridor.id.empty() || findCorridor(corridor.id) != nullptr)
        {
            return false;
        }

        corridors_.push_back(corridor);
        return true;
    }

    const RoutingCorridor* findCorridor(
        std::string_view id) const
    {
        for (const RoutingCorridor& corridor : corridors_)
        {
            if (corridor.id == id)
            {
                return &corridor;
            }
        }

        return nullptr;
    }

    const std::vector<RoutingCorridor>& corridors() const
    {
        return corridors_;
    }

    std::size_t size() const
    {
        return corridors_.size();
    }

    bool empty() const
    {
        return corridors_.empty();
    }

  private:
    std::vector<RoutingCorridor> corridors_;
};
