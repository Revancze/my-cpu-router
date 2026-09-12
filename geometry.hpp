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
