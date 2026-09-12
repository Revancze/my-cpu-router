#include "segment.hpp"
#include <cstdlib>

namespace
{
Point direction(
    const Point& from,
    const Point& to)
{
    return Point{to.x - from.x, to.y - from.y, to.z - from.z};
}

bool sameDirection(
    const Point& a,
    const Point& b)
{
    return a.x == b.x && a.y == b.y && a.z == b.z;
}
} // namespace

int Segment::length() const
{
    return std::abs(end.x - start.x) + std::abs(end.y - start.y) +
           std::abs(end.z - start.z);
}

std::vector<Segment> buildSegments(
    const Path& path)
{
    std::vector<Segment> segments;

    if (path.points.size() < 2)
        return segments;

    Point segmentStart = path.points[0];

    Point previousDirection = direction(path.points[0], path.points[1]);

    for (std::size_t i = 1; i + 1 < path.points.size(); ++i)
    {
        const Point currentDirection =
            direction(path.points[i], path.points[i + 1]);

        if (!sameDirection(previousDirection, currentDirection))
        {
            segments.push_back(Segment{segmentStart, path.points[i]});

            segmentStart = path.points[i];

            previousDirection = currentDirection;
        }
    }

    segments.push_back(Segment{segmentStart, path.points.back()});

    return segments;
}
