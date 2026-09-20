# CPU Router Roadmap

## Purpose

CPU Router is the main product of the repository.

Its long-term goal is to model, place, route, inspect, persist, and visualize
a CPU from low-level transistor structures upward while keeping logical
topology separate from physical geometry and routing.

The system is intended to support increasingly large designs without requiring
the entire routing space to be recomputed after every local modification.

The eventual workflow should support:

- automatic routing,
- guided routing,
- manual routing,
- hierarchical spatial partitioning,
- user-defined routing corridors,
- keep-out areas,
- routing rules,
- multiple routing layers,
- incremental rerouting,
- persistent route data,
- visualization and export.

Factorio remains a useful experimental and visualization target, but the core
architecture must not depend on Factorio.

Blender is a planned visualization target.

JSON is intended to remain the persistent source of truth for project data.

---

# Architectural principles

## Topology is not geometry

Logical connections describe what must be connected.

Placement describes where components exist.

Routing describes how those connections physically travel through space.

These systems must remain separate.

A logical net must not depend on a particular wire path.

---

## Routing data is not the spatial index

Persistent routing data belongs to the model.

Spatial structures exist only to accelerate queries.

Examples:

```text
RouteModel
    persistent truth

SpatialHierarchy
    spatial acceleration structure

RoutingPlan
    routing intent and policy

Router
    decision algorithm
```

Destroying and rebuilding a spatial index must never destroy the actual route
model.

---

## Stable identities

Long-lived objects must have stable identities independent of their current
position in memory or container ordering.

This eventually applies to:

```text
components
pins
nets
routes
route segments
routing regions
corridors
obstacles
constraints
```

Stable identities are required for persistence, incremental updates,
diagnostics, editing, and future GUI tools.

---

## Local changes should remain local

Changing a transistor, gate, component, route segment, or routing rule should
invalidate only the smallest practical affected area.

The router should prefer local recomputation over rebuilding the entire board.

Dirty-region tracking is therefore a fundamental part of the architecture.

---

## The routing universe is hierarchical

The physical CPU area is divided recursively into spatial regions.

The hierarchy should allow the router to reason at different scales.

Conceptually:

```text
GALAXY
└── quadrant
    └── sector
        └── region
            └── local routing area
```

Large-scale planning decides which general area a route should use.

Fine routing decides the exact path.

The router should not maintain a giant dense grid for the complete design when
only a small fraction of that space is currently relevant.

---

# Current foundation

The project already contains the beginning of the routing model.

Implemented or established concepts include:

```text
Point

RegionBounds

RoutingRegion

SpatialHierarchy

RoutingRequest

net-aware occupancy

pin-to-pin routing

component model

net identity
```

`RoutingRegion` uses recursive XY subdivision.

Each subdivision creates four XY children.

The Z dimension is not part of the quadtree split.

The number of routing layers is dynamic and must not be hard-coded to four.

Regions use half-open bounds:

```text
[min, max)
```

`SpatialHierarchy` performs lazy subdivision so the complete theoretical
routing grid does not need to exist in memory.

---

# R0 — Core routing model

Status: IN PROGRESS

Goal:

Establish stable primitive model types used by every higher routing layer.

Core concepts:

```text
Point
RegionBounds
NetId
Pin
Component
RoutingRequest
Route
RouteSegment
RouteModel
```

Requirements:

- shared geometry types,
- stable identities,
- explicit net ownership,
- no duplicate geometry definitions,
- no routing algorithm hidden inside model objects,
- testable standalone model components.

Exit condition:

The routing model can represent a route without requiring a particular spatial
index or visualization system.

---

# R1 — Spatial hierarchy

Status: IN PROGRESS

Existing work:

```text
RoutingRegion
SpatialHierarchy
lazy subdivision
dirty regions
XY quadtree
dynamic Z layers
```

Goal:

Provide scalable spatial lookup without allocating the complete routing space.

Required behavior:

```text
root region
maximum hierarchy depth
find leaf for a point
touch/create required hierarchy
mark region dirty
clear dirty state
bounds checking
lazy child creation
```

Future additions may include:

```text
region statistics
object counts
congestion information
dirty subtree propagation
debug visualization
```

Exit condition:

The router can efficiently locate and invalidate local areas without scanning
the complete CPU layout.

---

# R2 — RoutingPlan

Status: IN PROGRESS

Implemented foundation:

- RoutingPlan,
- RoutingCorridor,
- Preferred / Required / Forbidden policies,
- direction constraints,
- corridor priorities and conflict detection,
- router enforcement of hard constraints,
- Preferred direction routing cost.

RoutingPlan represents routing intent.

It does not contain the actual routed wires.

It tells the router where routes should preferably travel and which areas or
layers have special rules.

Conceptually:

```cpp
enum class RoutingPolicy {
    Preferred,
    Required,
    Forbidden
};

enum class RoutingDirection {
    Any,
    Horizontal,
    Vertical
};

struct RoutingCorridor {
    std::string id;
    RegionBounds bounds;
    RoutingPolicy policy{RoutingPolicy::Preferred};
    RoutingDirection direction{RoutingDirection::Any};
    int priority{};
};
```

RoutingPlan should eventually describe:

```text
preferred corridors
required corridors
forbidden regions
keep-out zones
preferred layers
allowed layers
routing direction
priority
routing cost modifiers
manual waypoints
locked route sections
```

This is the foundation of the future "galactic highway" system.

A user should eventually be able to define broad routing highways across the
CPU and allow the router to perform detailed routing inside them.

Important relationship:

```text
RoutingPlan
    says where routing should go

SpatialHierarchy
    says where things are

Router
    decides the path

RouteModel
    stores the resulting route
```

Exit condition:

Routing policy can be represented independently of both the routing algorithm
and the generated route geometry.

---

# R3 — Spatial object index

Status: DONE

Implemented:

- stable opaque object IDs,
- RegionBounds records,
- insert / remove / find operations,
- inside and intersection queries,
- half-open bounds semantics,
- spatial object kinds,
- optional net ownership,
- object-kind filtering,
- nearest-object lookup using Manhattan distance,
- deterministic nearest-object tie breaking,
- net occupancy queries,
- layer occupancy queries,
- local routing congestion reports,
- optional SpatialHierarchy acceleration,
- deepest containing-region storage,
- parent-region storage for cross-boundary objects,
- hierarchy-pruned candidate queries,
- best-first hierarchy traversal for nearest-object lookup.

Indexed object kinds include:

```text
pins
wire segments
vias
component bodies
obstacles
keep-out regions
routing corridors
```

The spatial index is an acceleration structure.

It remains reconstructible from persistent model data and is not the
authoritative storage for the design.

Supported queries include:

```text
objects inside region
objects intersecting region
objects filtered by kind
nearest object by kind
net occupancy
layer occupancy
routing congestion
```

Hierarchy-backed regional queries avoid scanning all indexed project objects.

Indexes without a SpatialHierarchy retain a linear fallback for correctness
and simple standalone use.

Exit condition:

Local routing can discover relevant nearby objects without scanning all project
objects.

Status: SATISFIED

---

# R4 — Local and incremental routing

Status: PLANNED

Goal:

A small edit must not reroute the complete processor.

The system should track affected routing regions.

Conceptual workflow:

```text
edit occurs
    ↓
affected objects identified
    ↓
affected regions marked dirty
    ↓
dependency impact calculated
    ↓
only required routes reconsidered
    ↓
new result validated
    ↓
transaction committed
```

Required concepts:

```text
dirty regions
route ownership
route dependencies
transactions
rollback
route preservation
local rerouting
```

Unchanged routes should remain stable whenever possible.

Exit condition:

Changing a local object causes bounded routing work instead of a global rebuild.

---

# R5 — Advanced net routing

Status: PLANNED

Extend routing beyond simple point-to-point connections.

Required future capabilities:

```text
multi-terminal nets
shared route trunks
branch routing
net-aware occupancy
capacity
congestion
routing cost
layer preference
vias
layer transitions
route conflict detection
```

The router should be able to distinguish:

```text
same-net occupancy
compatible shared route

different-net occupancy
routing conflict
```

Exit condition:

Real CPU nets containing multiple sinks and complex topology can be represented
and routed.

---

# R6 — Physical design rules

Status: PLANNED

The router must eventually understand rules derived from physical CPU
structure.

Examples:

```text
pin access
G / S / D restrictions
preferred entry direction
component boundaries
minimum spacing
reserved routing channels
layer-specific direction rules
forbidden crossings
```

Rules must be data-driven where practical.

They should not be scattered as hard-coded special cases throughout the router.

Exit condition:

Physical constraints can be added or modified without redesigning the complete
routing algorithm.

---

# R7 — Placement integration

Status: PLANNED

Routing eventually needs to cooperate with component placement.

Hierarchy may conceptually grow through levels such as:

```text
transistor
gate
cell
functional block
ALU / register / decoder
CPU subsystem
complete CPU
```

Placement must remain a separate system from routing.

The router consumes placement results but should not silently move components
unless explicitly operating through a placement/routing coordination layer.

Exit condition:

Real component layouts can provide routing inputs while preserving architecture
boundaries.

---

# R8 — Persistence

Status: PLANNED

Persistent project data should be representable in versioned JSON formats.

Potential files or logical sections:

```text
components
nets
placement
routing-plan
routes
constraints
metadata
```

Possible future route representation:

```text
route.json
```

Persistence must preserve:

```text
stable IDs
manual decisions
locked route sections
waypoints
routing corridors
keep-outs
layer assignments
generated routes
```

Internal spatial indexes should not need to be serialized unless there is a
clear performance reason.

They should normally be reconstructed from persistent model data.

Exit condition:

A project can be saved, loaded, edited, and routed again without losing user
intent.

---

# R9 — Routing modes

Status: PLANNED

The final router should support several levels of user control.

## AUTO

The router chooses the route automatically using RoutingPlan and physical rules.

```text
user:
    connect A to B

router:
    chooses everything
```

## GUIDED

The user supplies routing intent.

Examples:

```text
corridors
waypoints
preferred layer
forbidden region
required region
priority
```

The router still performs detailed routing.

## MANUAL

The user explicitly defines route geometry or selected route sections.

Manual sections should be lockable so automatic rerouting cannot silently
destroy them.

Exit condition:

Automatic routing and human design intent can coexist in one project.

---

# R10 — Visualization and diagnostics

Status: PLANNED

Routing must be observable.

Future visualization should expose:

```text
regions
dirty regions
hierarchy depth
pins
nets
routes
route ownership
obstacles
corridors
keep-outs
congestion
layer usage
routing failures
```

Initial exporters may use:

```text
OBJ
MTL
```

Blender is a planned major visualization target.

Factorio may remain an additional experimental visualization and interaction
target.

Exit condition:

A developer can visually inspect why the router made a routing decision.

---

# R11 — Interactive editor

Status: FUTURE

The long-term goal is an interactive design environment.

Potential operations:

```text
select component
select net
draw routing corridor
draw keep-out region
place waypoint
lock route
unlock route
reroute selected region
reroute selected net
inspect hierarchy
inspect congestion
change layer rules
```

The editor must operate through model APIs rather than directly mutating
internal router structures.

---

# R12 — CPU-scale integration

Status: FUTURE

The architecture must ultimately scale from individual transistor structures
toward a complete processor.

The project should be able to represent and visualize hierarchy from:

```text
nMOS / pMOS
    ↓
logic gate
    ↓
combinational block
    ↓
register / ALU / decoder
    ↓
functional unit
    ↓
CPU
```

The exact CPU architecture is not required to be fixed at this roadmap stage.

The routing architecture should remain sufficiently general to support future
experimentation.

---

# Performance strategy

The project should prefer sparse and hierarchical representations.

Avoid architectural assumptions requiring:

```text
one giant global dense grid
global reroute after every edit
linear scans over every route
hard-coded layer count
hard-coded CPU dimensions
hard-coded routing highways
```

Prefer:

```text
lazy hierarchy
local indexes
dirty regions
incremental updates
stable identities
reconstructible indexes
data-driven routing policy
```

Performance optimizations must preserve correctness and model clarity.

---

# Failure behavior

Routing failures are valid results and must be diagnosable.

The router should eventually explain failures such as:

```text
no legal path
capacity exhausted
forbidden region blocks route
required corridor unreachable
layer transition impossible
locked route conflict
physical rule violation
```

Failure must never silently corrupt unrelated routes.

---

# Testing strategy

Each architectural layer should have tests independent of higher layers.

Examples:

```text
geometry tests
region tests
hierarchy tests
routing-plan tests
occupancy tests
net identity tests
routing request tests
route persistence tests
incremental rerouting tests
failure tests
```

Large integration tests should complement, not replace, focused unit tests.

---

# Repository relationship

At present this repository contains two increasingly independent systems:

```text
CPU Router
    primary product

Codelaxy Tooling Engine
    development infrastructure
```

They intentionally remain in one repository while both are still evolving
together.

Long-term separation into independent repositories is expected once their
interfaces and responsibilities are sufficiently stable.

Possible future structure:

```text
my-cpu-router
    CPU routing and visualization project

codelaxy-engine
    StatusMan
    MrProper
    IronMan
    Doorman
    shared tooling engine
```

Repository separation must preserve useful Git history where practical.

The CPU Router should eventually consume Codelaxy as an external development
tool rather than containing its implementation.

---

# Near-term sequence

Current development should proceed approximately as:

```text
R0 core model
    ↓
R1 spatial hierarchy
    ↓
R2 RoutingPlan
    ↓
R3 spatial object index
    ↓
R4 incremental routing
    ↓
R5 advanced net routing
    ↓
physical rules / placement / persistence / visualization
```

The roadmap is architectural guidance, not a requirement to implement every
future feature before continuing useful CPU development.

Each milestone should leave the repository buildable, testable, and reviewable.
