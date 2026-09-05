#pragma once

#include "route_model.hpp"

#include <string>

bool saveRoute(
    const RouteModel& model,
    const std::string& filename,
    std::string& error);

bool loadRoute(
    const std::string& filename,
    RouteModel& model,
    std::string& error);