#include "transistor_model.hpp"


// ============================================================
// TRANSISTOR TYPE
// ============================================================

const char* transistorTypeName(
    TransistorType type)
{
    switch (type)
    {
    case TransistorType::NMOS:
        return "NMOS";

    case TransistorType::PMOS:
        return "PMOS";
    }

    return "UNKNOWN";
}


// ============================================================
// TRANSISTOR FACTORY
// ============================================================

Component makeTransistor(
    const std::string& id,
    TransistorType type,
    Point position)
{
    Component transistor;

    transistor.id = id;

    transistor.type = transistorTypeName(type);

    transistor.position = position;

    transistor.pins = {Pin{"G", Point{position.x - 1, position.y, position.z}},

                       Pin{"S", Point{position.x, position.y - 1, position.z}},

                       Pin{"D", Point{position.x, position.y + 1, position.z}}};

    return transistor;
}
