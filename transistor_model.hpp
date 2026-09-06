#pragma once

#include "component_model.hpp"

#include <string>


// ============================================================
// TRANSISTOR TYPE
// ============================================================

enum class TransistorType
{
    NMOS,
    PMOS
};


// ============================================================
// TRANSISTOR HELPERS
// ============================================================

const char* transistorTypeName(
    TransistorType type);


// ============================================================
// TRANSISTOR FACTORY
// ============================================================

Component makeTransistor(
    const std::string& id,
    TransistorType type,
    Point position);
