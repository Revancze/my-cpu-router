#include "transistor_model.hpp"

#include <cassert>
#include <iostream>

int main()
{
    Component nmos =
        makeTransistor("N1", TransistorType::NMOS, Point{10, 10, 0});

    Component pmos =
        makeTransistor("P1", TransistorType::PMOS, Point{20, 10, 0});

    assert(nmos.id == "N1");
    assert(nmos.type == "NMOS");
    assert(nmos.pins.size() == 3);

    assert(pmos.id == "P1");
    assert(pmos.type == "PMOS");
    assert(pmos.pins.size() == 3);

    const Pin* nmosGate = nmos.findPin("G");

    const Pin* nmosSource = nmos.findPin("S");

    const Pin* nmosDrain = nmos.findPin("D");

    assert(nmosGate != nullptr);
    assert(nmosSource != nullptr);
    assert(nmosDrain != nullptr);

    assert((nmosGate->position == Point{9, 10, 0}));

    assert((nmosSource->position == Point{10, 9, 0}));

    assert((nmosDrain->position == Point{10, 11, 0}));

    std::cout << "NMOS: " << nmos.id << " pins=" << nmos.pins.size() << '\n';

    std::cout << "PMOS: " << pmos.id << " pins=" << pmos.pins.size() << '\n';

    std::cout << "G=(" << nmosGate->position.x << "," << nmosGate->position.y
              << "," << nmosGate->position.z << ")\n";

    std::cout << "S=(" << nmosSource->position.x << ","
              << nmosSource->position.y << "," << nmosSource->position.z
              << ")\n";

    std::cout << "D=(" << nmosDrain->position.x << "," << nmosDrain->position.y
              << "," << nmosDrain->position.z << ")\n";

    std::cout << "transistor_model test: PASS\n";

    return 0;
}
