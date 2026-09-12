#include "router.hpp"

#include <cassert>
#include <iostream>
#include <optional>

int main()
{
    const NetId netA = "NET_A";
    const NetId netB = "NET_B";

    Router router(5, 1, 1);

    Path existingWire;

    existingWire.points = {
        Point{1, 0, 0},
        Point{2, 0, 0},
        Point{3, 0, 0},
    };

    router.commitPath(existingWire, netA);

    const Point middle{2, 0, 0};

    assert(router.isWire(middle));

    const std::optional<NetId> owner = router.wireOwner(middle);

    assert(owner.has_value());
    assert(owner.value() == netA);

    assert(!router.isBlocked(middle, netA));
    assert(router.isBlocked(middle, netB));

    const Path sameNetPath =
        router.findPath(Point{0, 0, 0}, Point{4, 0, 0}, netA);

    assert(sameNetPath.found());
    assert(sameNetPath.length() == 4);

    const Path foreignNetPath =
        router.findPath(Point{0, 0, 0}, Point{4, 0, 0}, netB);

    assert(!foreignNetPath.found());

    const Path legacyPath = router.findPath(Point{0, 0, 0}, Point{4, 0, 0});

    assert(!legacyPath.found());

    Router anonymousRouter(3, 1, 1);

    Path anonymousWire;

    anonymousWire.points = {
        Point{1, 0, 0},
    };

    anonymousRouter.commitPath(anonymousWire);

    assert(anonymousRouter.isWire(Point{1, 0, 0}));

    assert(!anonymousRouter.wireOwner(Point{1, 0, 0}).has_value());

    assert(!anonymousRouter.findPath(Point{0, 0, 0}, Point{2, 0, 0}, netA)
                .found());

    std::cout << "Owner: " << owner.value() << '\n';
    std::cout << "Same-net route length: " << sameNetPath.length() << '\n';
    std::cout << "Foreign-net route: blocked\n";
    std::cout << "Legacy anonymous wire: blocked\n";
    std::cout << "net-aware occupancy test: PASS\n";

    return 0;
}
