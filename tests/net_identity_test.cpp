#include "component_model.hpp"
#include "net_id.hpp"
#include "route_model.hpp"

#include <cassert>
#include <iostream>
#include <string>
#include <type_traits>

int main()
{
    static_assert(std::is_same_v<NetId, std::string>);

    const NetId netId = "NET_DATA";

    Net net;
    net.name = netId;

    Wire wire;
    wire.netName = netId;

    assert(net.name == netId);
    assert(wire.netName == netId);
    assert(net.name == wire.netName);

    ComponentModel model;

    model.addNet(net);

    Net* foundNet = model.findNet(netId);

    assert(foundNet != nullptr);
    assert(foundNet->name == netId);

    std::cout << "NetId: " << netId << '\n';

    std::cout << "Logical net: " << foundNet->name << '\n';

    std::cout << "Physical wire net: " << wire.netName << '\n';

    std::cout << "net_identity test: PASS\n";

    return 0;
}
