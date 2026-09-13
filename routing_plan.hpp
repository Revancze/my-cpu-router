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
// ROUTING DECISION
// ============================================================

enum class RoutingDecision
{
    Unconstrained,
    Preferred,
    Required,
    Forbidden,
    Conflict
};

struct RoutingDecisionResult
{
    RoutingDecision decision{RoutingDecision::Unconstrained};
    RoutingDirection direction{RoutingDirection::Any};
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

    RoutingDecisionResult evaluate(
        Point point) const
    {
        Candidate required;
        Candidate preferred;

        for (const RoutingCorridor& corridor : corridors_)
        {
            if (!corridor.bounds.contains(point))
            {
                continue;
            }

            if (corridor.policy == RoutingPolicy::Forbidden)
            {
                return {RoutingDecision::Forbidden, RoutingDirection::Any};
            }

            if (corridor.policy == RoutingPolicy::Required)
            {
                consider(required, corridor);
                continue;
            }

            consider(preferred, corridor);
        }

        if (required.found)
        {
            if (required.conflict)
            {
                return {RoutingDecision::Conflict, RoutingDirection::Any};
            }

            return {RoutingDecision::Required, required.direction};
        }

        if (preferred.found)
        {
            if (preferred.conflict)
            {
                return {RoutingDecision::Conflict, RoutingDirection::Any};
            }

            return {RoutingDecision::Preferred, preferred.direction};
        }

        return {};
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
    struct Candidate
    {
        bool found{};
        bool conflict{};

        int priority{};

        RoutingDirection direction{RoutingDirection::Any};
    };

    static bool directionsConflict(
        RoutingDirection lhs,
        RoutingDirection rhs)
    {
        return lhs != RoutingDirection::Any && rhs != RoutingDirection::Any &&
               lhs != rhs;
    }

    static RoutingDirection mergeDirections(
        RoutingDirection lhs,
        RoutingDirection rhs)
    {
        if (lhs == RoutingDirection::Any)
        {
            return rhs;
        }

        if (rhs == RoutingDirection::Any)
        {
            return lhs;
        }

        return lhs;
    }

    static void consider(
        Candidate& candidate,
        const RoutingCorridor& corridor)
    {
        if (!candidate.found || corridor.priority > candidate.priority)
        {
            candidate.found = true;
            candidate.conflict = false;
            candidate.priority = corridor.priority;
            candidate.direction = corridor.direction;
            return;
        }

        if (corridor.priority < candidate.priority)
        {
            return;
        }

        if (directionsConflict(candidate.direction, corridor.direction))
        {
            candidate.conflict = true;
            return;
        }

        candidate.direction =
            mergeDirections(candidate.direction, corridor.direction);
    }

    std::vector<RoutingCorridor> corridors_;
};
