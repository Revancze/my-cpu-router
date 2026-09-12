#pragma once

#include "route_model.hpp"

#include <string>

bool exportObj(const RouteModel& model,
               const std::string& filename,
               std::string& error);
