#pragma once

#include "router.hpp"

#include <vector>

struct Segment
{
    Point start;
    Point end;

    int length() const;
};

std::vector<Segment> buildSegments(const Path& path);