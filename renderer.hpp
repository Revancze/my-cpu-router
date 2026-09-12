#pragma once

#include "route_model.hpp"

#include <vector>

enum class View
{
    Top,
    Side
};

class Renderer
{
  public:
    Renderer(int width, int height, int layers);

    void render(const RouteModel& model, View view) const;

  private:
    int width_;
    int height_;
    int layers_;

    void renderTop(const std::vector<Wire>& wires) const;

    void renderSide(const std::vector<Wire>& wires) const;

    char glyphTop(const std::vector<Wire>& wires, int x, int y) const;

    char glyphSide(const std::vector<Wire>& wires, int y, int z) const;

    bool hasVerticalConnection(const std::vector<Wire>& wires,
                               int y,
                               int lowerZ) const;
};
