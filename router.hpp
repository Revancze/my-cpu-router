#pragma once

#include <vector>

struct Point
{
    int x{};
    int y{};
    int z{};

    bool operator==(const Point& other) const
    {
        return x == other.x &&
               y == other.y &&
               z == other.z;
    }
};

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

class Router
{
public:
    Router(
        int width,
        int height,
        int layers,
        int turnPenalty = 3,
        int layerChangePenalty = 2,
        int upperLayerStepPenalty = 1);

    void addObstacle(Point p);

    Path findPath(Point start, Point end) const;

    void commitPath(const Path& path);

    bool isInside(Point p) const;
    bool isObstacle(Point p) const;
    bool isWire(Point p) const;
    bool isBlocked(Point p) const;

private:
    int width_;
    int height_;
    int layers_;

    int turnPenalty_;
    int layerChangePenalty_;
    int upperLayerStepPenalty_;

    std::vector<
        std::vector<
            std::vector<bool>>> obstacles_;

    std::vector<
        std::vector<
            std::vector<bool>>> wires_;
};