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

    // --------------------------------------------------------
    // COMMIT MUST NOT STEAL A CELL FROM ANOTHER NET
    // --------------------------------------------------------

    Router ownershipRouter(3, 1, 1);

    Path netAPath;
    netAPath.points = {
        Point{1, 0, 0},
    };

    assert(ownershipRouter.commitPath(netAPath, netA));

    assert(ownershipRouter.wireOwner(Point{1, 0, 0}).has_value());
    assert(ownershipRouter.wireOwner(Point{1, 0, 0}).value() == netA);

    Path conflictingNetBPath;
    conflictingNetBPath.points = {
        Point{1, 0, 0},
    };

    assert(!ownershipRouter.commitPath(conflictingNetBPath, netB));

    assert(ownershipRouter.wireOwner(Point{1, 0, 0}).has_value());
    assert(ownershipRouter.wireOwner(Point{1, 0, 0}).value() == netA);

    Router atomicRouter(4, 1, 1);

    Path occupiedByNetA;
    occupiedByNetA.points = {
        Point{2, 0, 0},
    };

    assert(atomicRouter.commitPath(occupiedByNetA, netA));

    Path conflictingPath;
    conflictingPath.points = {
        Point{1, 0, 0},
        Point{2, 0, 0},
        Point{3, 0, 0},
    };

    assert(!atomicRouter.commitPath(conflictingPath, netB));

    assert(!atomicRouter.isWire(Point{1, 0, 0}));
    assert(atomicRouter.wireOwner(Point{2, 0, 0}).has_value());
    assert(atomicRouter.wireOwner(Point{2, 0, 0}).value() == netA);
    assert(!atomicRouter.isWire(Point{3, 0, 0}));

    // --------------------------------------------------------
    // ANONYMOUS COMMIT MUST NOT STEAL OWNED WIRE
    // --------------------------------------------------------

    Router anonymousOwnershipRouter(3, 1, 1);

    Path ownedPath;
    ownedPath.points = {
        Point{1, 0, 0},
    };

    assert(anonymousOwnershipRouter.commitPath(ownedPath, netA));

    assert(anonymousOwnershipRouter.wireOwner(Point{1, 0, 0}).has_value());
    assert(anonymousOwnershipRouter.wireOwner(Point{1, 0, 0}).value() == netA);

    Path anonymousOverwritePath;
    anonymousOverwritePath.points = {
        Point{1, 0, 0},
    };

    assert(!anonymousOwnershipRouter.commitPath(anonymousOverwritePath));

    assert(anonymousOwnershipRouter.wireOwner(Point{1, 0, 0}).has_value());
    assert(anonymousOwnershipRouter.wireOwner(Point{1, 0, 0}).value() == netA);
    Router anonymousAtomicRouter(4, 1, 1);

    Path ownedMiddle;
    ownedMiddle.points = {
        Point{2, 0, 0},
    };

    assert(anonymousAtomicRouter.commitPath(ownedMiddle, netA));

    Path anonymousConflictingPath;
    anonymousConflictingPath.points = {
        Point{1, 0, 0},
        Point{2, 0, 0},
        Point{3, 0, 0},
    };

    assert(!anonymousAtomicRouter.commitPath(anonymousConflictingPath));

    assert(!anonymousAtomicRouter.isWire(Point{1, 0, 0}));
    assert(anonymousAtomicRouter.wireOwner(Point{2, 0, 0}).has_value());
    assert(anonymousAtomicRouter.wireOwner(Point{2, 0, 0}).value() == netA);
    assert(!anonymousAtomicRouter.isWire(Point{3, 0, 0}));

    // --------------------------------------------------------
    // COMMIT MUST NOT CROSS AN OBSTACLE
    // --------------------------------------------------------

    Router obstacleCommitRouter(4, 1, 1);

    obstacleCommitRouter.addObstacle(Point{2, 0, 0});

    Path obstaclePath;
    obstaclePath.points = {
        Point{1, 0, 0},
        Point{2, 0, 0},
        Point{3, 0, 0},
    };

    assert(!obstacleCommitRouter.commitPath(obstaclePath, netA));

    assert(!obstacleCommitRouter.isWire(Point{1, 0, 0}));
    assert(!obstacleCommitRouter.isWire(Point{2, 0, 0}));
    assert(!obstacleCommitRouter.isWire(Point{3, 0, 0}));

    Router anonymousObstacleRouter(4, 1, 1);

    anonymousObstacleRouter.addObstacle(Point{2, 0, 0});

    assert(!anonymousObstacleRouter.commitPath(obstaclePath));

    assert(!anonymousObstacleRouter.isWire(Point{1, 0, 0}));
    assert(!anonymousObstacleRouter.isWire(Point{2, 0, 0}));
    assert(!anonymousObstacleRouter.isWire(Point{3, 0, 0}));

    // --------------------------------------------------------
    // COMMIT MUST REJECT OUT-OF-BOUNDS PATHS
    // --------------------------------------------------------

    Router boundsCommitRouter(4, 1, 1);

    Path outOfBoundsPath;
    outOfBoundsPath.points = {
        Point{1, 0, 0},
        Point{4, 0, 0},
        Point{2, 0, 0},
    };

    assert(!boundsCommitRouter.commitPath(outOfBoundsPath, netA));

    assert(!boundsCommitRouter.isWire(Point{1, 0, 0}));
    assert(!boundsCommitRouter.isWire(Point{2, 0, 0}));

    Router anonymousBoundsRouter(4, 1, 1);

    assert(!anonymousBoundsRouter.commitPath(outOfBoundsPath));

    assert(!anonymousBoundsRouter.isWire(Point{1, 0, 0}));
    assert(!anonymousBoundsRouter.isWire(Point{2, 0, 0}));

    // --------------------------------------------------------
    // COMMIT MUST REJECT STRUCTURALLY INVALID PATHS
    // --------------------------------------------------------

    Router structuralRouter(5, 2, 1);

    Path emptyPath;

    assert(!structuralRouter.commitPath(emptyPath, netA));
    assert(!structuralRouter.commitPath(emptyPath));

    Path disconnectedPath;
    disconnectedPath.points = {
        Point{1, 0, 0},
        Point{3, 0, 0},
    };

    assert(!structuralRouter.commitPath(disconnectedPath, netA));

    assert(!structuralRouter.isWire(Point{1, 0, 0}));
    assert(!structuralRouter.isWire(Point{3, 0, 0}));

    assert(!structuralRouter.commitPath(disconnectedPath));

    assert(!structuralRouter.isWire(Point{1, 0, 0}));
    assert(!structuralRouter.isWire(Point{3, 0, 0}));

    Path diagonalPath;
    diagonalPath.points = {
        Point{0, 0, 0},
        Point{1, 1, 0},
    };

    assert(!structuralRouter.commitPath(diagonalPath, netA));

    assert(!structuralRouter.isWire(Point{0, 0, 0}));
    assert(!structuralRouter.isWire(Point{1, 1, 0}));

    Path repeatedPointPath;
    repeatedPointPath.points = {
        Point{2, 1, 0},
        Point{2, 1, 0},
    };

    assert(!structuralRouter.commitPath(repeatedPointPath, netA));

    assert(!structuralRouter.isWire(Point{2, 1, 0}));

    std::cout << "Owner: " << owner.value() << '\n';
    std::cout << "Same-net route length: " << sameNetPath.length() << '\n';
    std::cout << "Foreign-net route: blocked\n";
    std::cout << "Legacy anonymous wire: blocked\n";
    std::cout << "net-aware occupancy test: PASS\n";

    return 0;
}
