#pragma once

#include "geometry.hpp"
#include "net_id.hpp"

#include <optional>
#include <vector>


struct Path
{
    std::vector<Point> points;

    int totalCost{};
    int turns{};
    int layerChanges{};

    bool found() const
    {
        return !points.empty();
    }

    int length() const
    {
        if (points.empty())
            return 0;

        return static_cast<int>(points.size()) - 1;
    }
};

class RoutingPlan;

class Router
{
  public:
    Router(int width,
           int height,
           int layers,
           int turnPenalty = 3,
           int layerChangePenalty = 2,
           int upperLayerStepPenalty = 1,
           int preferredDirectionPenalty = 1);

    void addObstacle(Point p);

    Path findPath(Point start, Point end) const;

    Path findPath(Point start, Point end, const RoutingPlan& plan) const;

    Path findPath(Point start,
                  Point end,
                  const NetId& netId,
                  const RoutingPlan& plan) const;

    Path findPath(Point start, Point end, const NetId& netId) const;

    bool commitPath(const Path& path);

    bool commitPath(const Path& path, const NetId& netId);

    bool isInside(Point p) const;
    bool isObstacle(Point p) const;
    bool isWire(Point p) const;
    bool isBlocked(Point p) const;

    bool isBlocked(Point p, const NetId& netId) const;

    std::optional<NetId> wireOwner(Point p) const;

  private:
    struct WireCell
    {
        bool occupied{};
        std::optional<NetId> owner;
    };

    Path findPathImpl(Point start,
                      Point end,
                      const NetId* netId,
                      const RoutingPlan* plan) const;

    int width_;
    int height_;
    int layers_;

    int turnPenalty_;
    int layerChangePenalty_;
    int upperLayerStepPenalty_;
    int preferredDirectionPenalty_;

    std::vector<std::vector<std::vector<bool>>> obstacles_;

    std::vector<std::vector<std::vector<WireCell>>> wires_;
};
