#include "router.hpp"

#include <algorithm>
#include <array>
#include <limits>
#include <queue>
#include <vector>

namespace
{
constexpr int DIR_RIGHT = 0;
constexpr int DIR_LEFT = 1;
constexpr int DIR_DOWN = 2;
constexpr int DIR_UP = 3;
constexpr int DIR_Z_UP = 4;
constexpr int DIR_Z_DOWN = 5;
constexpr int DIR_NONE = 6;

constexpr int DIR_COUNT = 7;

constexpr std::array<Point, 6> directions = {Point{1, 0, 0},
                                             Point{-1, 0, 0},
                                             Point{0, 1, 0},
                                             Point{0, -1, 0},
                                             Point{0, 0, 1},
                                             Point{0, 0, -1}};

bool isPlanarDirection(
    int dir)
{
    return dir >= 0 && dir <= 3;
}

struct State
{
    int x{};
    int y{};
    int z{};
    int dir{};
};

struct QueueNode
{
    int cost{};
    State state{};

    bool operator>(
        const QueueNode& other) const
    {
        return cost > other.cost;
    }
};
} // namespace

Router::Router(
    int width,
    int height,
    int layers,
    int turnPenalty,
    int layerChangePenalty,
    int upperLayerStepPenalty)
    : width_(width), height_(height), layers_(layers),
      turnPenalty_(turnPenalty), layerChangePenalty_(layerChangePenalty),
      upperLayerStepPenalty_(upperLayerStepPenalty),
      obstacles_(
          layers,
          std::vector<std::vector<bool>>(height,
                                         std::vector<bool>(width, false))),
      wires_(layers,
             std::vector<std::vector<bool>>(height,
                                            std::vector<bool>(width, false)))
{
}

bool Router::isInside(
    Point p) const
{
    return p.x >= 0 && p.y >= 0 && p.z >= 0 && p.x < width_ && p.y < height_ &&
           p.z < layers_;
}

bool Router::isObstacle(
    Point p) const
{
    if (!isInside(p))
        return true;

    return obstacles_[p.z][p.y][p.x];
}

bool Router::isWire(
    Point p) const
{
    if (!isInside(p))
        return false;

    return wires_[p.z][p.y][p.x];
}

bool Router::isBlocked(
    Point p) const
{
    if (!isInside(p))
        return true;

    return isObstacle(p) || isWire(p);
}

void Router::addObstacle(
    Point p)
{
    if (isInside(p))
        obstacles_[p.z][p.y][p.x] = true;
}

void Router::commitPath(
    const Path& path)
{
    for (const Point p : path.points)
    {
        if (isInside(p))
            wires_[p.z][p.y][p.x] = true;
    }
}

Path Router::findPath(
    Point start,
    Point end) const
{
    Path result;

    if (!isInside(start) || !isInside(end) || isBlocked(start) ||
        isBlocked(end))
    {
        return result;
    }

    if (start == end)
    {
        result.points.push_back(start);
        return result;
    }

    const int stateCount = width_ * height_ * layers_ * DIR_COUNT;

    const int INF = std::numeric_limits<int>::max();

    std::vector<int> distance(stateCount, INF);

    std::vector<State> parent(stateCount, State{-1, -1, -1, -1});

    auto indexOf = [this](int x, int y, int z, int dir)
    {
        return ((((z * height_) + y) * width_ + x) * DIR_COUNT) + dir;
    };

    std::priority_queue<QueueNode,
                        std::vector<QueueNode>,
                        std::greater<QueueNode>>
        queue;

    State startState{start.x, start.y, start.z, DIR_NONE};

    distance[indexOf(start.x, start.y, start.z, DIR_NONE)] = 0;

    queue.push(QueueNode{0, startState});

    while (!queue.empty())
    {
        QueueNode currentNode = queue.top();

        queue.pop();

        State current = currentNode.state;

        const int currentIndex =
            indexOf(current.x, current.y, current.z, current.dir);

        if (currentNode.cost != distance[currentIndex])
        {
            continue;
        }

        for (int nextDir = 0; nextDir < 6; ++nextDir)
        {
            Point next{current.x + directions[nextDir].x,
                       current.y + directions[nextDir].y,
                       current.z + directions[nextDir].z};

            if (!isInside(next))
                continue;

            if (isBlocked(next))
                continue;

            int stepCost = 1;

            // Pohyb mezi vrstvami.
            if (nextDir == DIR_Z_UP || nextDir == DIR_Z_DOWN)
            {
                stepCost += layerChangePenalty_;
            }
            else
            {
                // Pohyb po horni vrstve je trochu drazsi,
                // aby router nedelal zbytecne dlouhe mosty.
                if (next.z > 0)
                {
                    stepCost += upperLayerStepPenalty_;
                }

                // Penalizace zatacky pouze v rovine XY.
                if (current.dir != DIR_NONE && isPlanarDirection(current.dir) &&
                    current.dir != nextDir)
                {
                    stepCost += turnPenalty_;
                }
            }

            const int newCost = currentNode.cost + stepCost;

            const int nextIndex = indexOf(next.x, next.y, next.z, nextDir);

            if (newCost < distance[nextIndex])
            {
                distance[nextIndex] = newCost;

                parent[nextIndex] = current;

                queue.push(
                    QueueNode{newCost, State{next.x, next.y, next.z, nextDir}});
            }
        }
    }

    int bestDir = -1;
    int bestCost = INF;

    for (int dir = 0; dir < 6; ++dir)
    {
        const int index = indexOf(end.x, end.y, end.z, dir);

        if (distance[index] < bestCost)
        {
            bestCost = distance[index];

            bestDir = dir;
        }
    }

    if (bestDir == -1)
        return result;

    State current{end.x, end.y, end.z, bestDir};

    while (!(current.x == start.x && current.y == start.y &&
             current.z == start.z && current.dir == DIR_NONE))
    {
        result.points.push_back(Point{current.x, current.y, current.z});

        const int currentIndex =
            indexOf(current.x, current.y, current.z, current.dir);

        current = parent[currentIndex];
    }

    result.points.push_back(start);

    std::reverse(result.points.begin(), result.points.end());

    result.totalCost = bestCost;

    // Spocitame XY zatacky a zmeny vrstvy.
    bool havePreviousPlanarDirection = false;

    int previousDx = 0;
    int previousDy = 0;

    for (std::size_t i = 1; i < result.points.size(); ++i)
    {
        const int dx = result.points[i].x - result.points[i - 1].x;

        const int dy = result.points[i].y - result.points[i - 1].y;

        const int dz = result.points[i].z - result.points[i - 1].z;

        if (dz != 0)
        {
            ++result.layerChanges;
            continue;
        }

        if (havePreviousPlanarDirection &&
            (dx != previousDx || dy != previousDy))
        {
            ++result.turns;
        }

        previousDx = dx;
        previousDy = dy;

        havePreviousPlanarDirection = true;
    }

    return result;
}
