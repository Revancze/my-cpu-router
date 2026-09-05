#include "renderer.hpp"
#include "route_model.hpp"

#include <iostream>
#include <utility>

namespace
{
    template <typename Project>
    char glyphForWire(
        const Wire& wire,
        int cellX,
        int cellY,
        Project project)
    {
        bool present = false;

        bool horizontal = false;
        bool vertical = false;

        bool endpoint = false;

        if (wire.path.points.empty())
            return '.';

        const auto first =
            project(wire.path.points.front());

        const auto last =
            project(wire.path.points.back());

        if ((first.first == cellX &&
             first.second == cellY) ||
            (last.first == cellX &&
             last.second == cellY))
        {
            endpoint = true;
        }

        for (const Point& p : wire.path.points)
        {
            const auto projected =
                project(p);

            if (projected.first == cellX &&
                projected.second == cellY)
            {
                present = true;
            }
        }

        for (std::size_t i = 1;
             i < wire.path.points.size();
             ++i)
        {
            const auto a =
                project(
                    wire.path.points[i - 1]);

            const auto b =
                project(
                    wire.path.points[i]);

            // Pohyb v ose, kterou v dane projekci nevidime.
            if (a == b)
                continue;

            if ((a.first == cellX &&
                 a.second == cellY) ||
                (b.first == cellX &&
                 b.second == cellY))
            {
                if (a.first != b.first)
                    horizontal = true;

                if (a.second != b.second)
                    vertical = true;
            }
        }

        if (!present)
            return '.';

        if (endpoint)
            return wire.name;

        if (horizontal && vertical)
            return '+';

        if (horizontal)
            return '-';

        if (vertical)
            return '|';

        return wire.name;
    }
}

Renderer::Renderer(
    int width,
    int height,
    int layers)
    : width_(width),
      height_(height),
      layers_(layers)
{
}

char Renderer::glyphTop(
    const std::vector<Wire>& wires,
    int x,
    int y) const
{
    char result = '.';
    int count = 0;

    for (const Wire& wire : wires)
    {
        const char glyph =
            glyphForWire(
                wire,
                x,
                y,
                [](Point p)
                {
                    return std::pair{
                        p.x,
                        p.y
                    };
                });

        if (glyph != '.')
        {
            result = glyph;
            ++count;
        }
    }

    // Dva ruzne draty mohou byt na stejnem X/Y,
    // ale v rozdilnych vrstvach Z.
    if (count > 1)
        return '*';

    return result;
}

char Renderer::glyphSide(
    const std::vector<Wire>& wires,
    int y,
    int z) const
{
    char result = '.';
    int count = 0;

    for (const Wire& wire : wires)
    {
        const char glyph =
            glyphForWire(
                wire,
                y,
                z,
                [](Point p)
                {
                    // SIDE VIEW:
                    // divame se ve smeru osy X.
                    //
                    // Horizontalne = Y
                    // Vertikalne   = Z
                    return std::pair{
                        p.y,
                        p.z
                    };
                });

        if (glyph != '.')
        {
            result = glyph;
            ++count;
        }
    }

    if (count > 1)
        return '*';

    return result;
}

bool Renderer::hasVerticalConnection(
    const std::vector<Wire>& wires,
    int y,
    int lowerZ) const
{
    for (const Wire& wire : wires)
    {
        for (std::size_t i = 1;
             i < wire.path.points.size();
             ++i)
        {
            const Point a =
                wire.path.points[i - 1];

            const Point b =
                wire.path.points[i];

            if (a.y != y ||
                b.y != y)
            {
                continue;
            }

            if (a.x != b.x)
                continue;

            if ((a.z == lowerZ &&
                 b.z == lowerZ + 1) ||
                (b.z == lowerZ &&
                 a.z == lowerZ + 1))
            {
                return true;
            }
        }
    }

    return false;
}

void Renderer::renderTop(
    const std::vector<Wire>& wires) const
{
    std::cout
        << "=== TOP VIEW (X/Y) ===\n";

    for (int y = 0;
         y < height_;
         ++y)
    {
        for (int x = 0;
             x < width_;
             ++x)
        {
            std::cout
                << glyphTop(
                    wires,
                    x,
                    y);
        }

        std::cout << '\n';
    }
}

void Renderer::renderSide(
    const std::vector<Wire>& wires) const
{
    std::cout
        << "=== SIDE VIEW (Y/Z) ===\n";

    for (int z = layers_ - 1;
         z >= 0;
         --z)
    {
        std::cout
            << "z="
            << z
            << " ";

        for (int y = 0;
             y < height_;
             ++y)
        {
            std::cout
                << glyphSide(
                    wires,
                    y,
                    z);
        }

        std::cout << '\n';

        // Mezi vrstvami vykreslime svisle spojeni.
        if (z > 0)
        {
            std::cout << "    ";

            for (int y = 0;
                 y < height_;
                 ++y)
            {
                if (hasVerticalConnection(
                        wires,
                        y,
                        z - 1))
                {
                    std::cout << '|';
                }
                else
                {
                    std::cout << ' ';
                }
            }

            std::cout << '\n';
        }
    }
}

void Renderer::render(
    const RouteModel& model,
    View view) const
{
    switch (view)
    {
        case View::Top:
            renderTop(model.wires);
            break;

        case View::Side:
            renderSide(model.wires);
            break;
    }
}