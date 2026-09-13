#pragma once

struct Point
{
    int x{};
    int y{};
    int z{};

    bool operator==(
        const Point& other) const
    {
        return x == other.x && y == other.y && z == other.z;
    }
};

struct RegionBounds
{
    int minX{};
    int minY{};
    int minZ{};

    int maxX{};
    int maxY{};
    int maxZ{};

    bool contains(
        Point p) const
    {
        return p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY &&
               p.z >= minZ && p.z < maxZ;
    }

    int width() const
    {
        return maxX - minX;
    }

    int height() const
    {
        return maxY - minY;
    }

    int layers() const
    {
        return maxZ - minZ;
    }
};
