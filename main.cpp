#include "router.hpp"
#include "renderer.hpp"
#include "segment.hpp"
#include "route_model.hpp"
#include "route_io.hpp"
#include "obj_exporter.hpp"

#include <filesystem>
#include <iostream>
#include <string>


// ============================================================
// FILE NAME
// ============================================================

std::string normalizeRouteFilename(
    const std::string& filename)
{
    if (filename.empty())
        return "route.json";

    std::filesystem::path path(filename);

    if (!path.has_extension())
    {
        path += ".json";
        return path.string();
    }

    if (path.extension() == ".json")
    {
        return path.string();
    }

    return {};
}


// ============================================================
// TEXT HELPERS
// ============================================================

const char* netTypeName(
    NetType type)
{
    switch (type)
    {
        case NetType::Signal:
            return "SIGNAL";

        case NetType::VDD:
            return "VDD";

        case NetType::VSS:
            return "VSS";
    }

    return "UNKNOWN";
}


const char* factorioWireName(
    FactorioWire wire)
{
    switch (wire)
    {
        case FactorioWire::None:
            return "NONE";

        case FactorioWire::Red:
            return "RW";

        case FactorioWire::Green:
            return "GW";
    }

    return "UNKNOWN";
}


// ============================================================
// DEBUG OUTPUT
// ============================================================

void printWireInfo(
    const Wire& wire)
{
    std::cout
        << "WIRE "
        << wire.name
        << '\n';

    std::cout
        << "Net: "
        << wire.netName
        << '\n';

    std::cout
        << "Type: "
        << netTypeName(
               wire.netType)
        << '\n';

    std::cout
        << "Factorio wire: "
        << factorioWireName(
               wire.factorioWire)
        << '\n';

    std::cout
        << "Length: "
        << wire.path.length()
        << '\n';

    std::cout
        << "Turns: "
        << wire.path.turns
        << '\n';

    std::cout
        << "Layer changes: "
        << wire.path.layerChanges
        << '\n';

    std::cout
        << "Cost: "
        << wire.path.totalCost
        << "\n\n";
}


void printSegments(
    const Wire& wire)
{
    std::cout
        << "SEGMENTS "
        << wire.name
        << '\n';

    for (std::size_t i = 0;
         i < wire.segments.size();
         ++i)
    {
        const Segment& s =
            wire.segments[i];

        std::cout
            << i + 1
            << ": ("
            << s.start.x << ","
            << s.start.y << ","
            << s.start.z << ") -> ("
            << s.end.x << ","
            << s.end.y << ","
            << s.end.z << ")"
            << " length="
            << s.length()
            << '\n';
    }

    std::cout << '\n';
}


void showModel(
    const RouteModel& model)
{
    for (const Wire& wire :
         model.wires)
    {
        printWireInfo(wire);
        printSegments(wire);
    }

    Renderer renderer(
        model.width,
        model.height,
        model.layers);

    renderer.render(
        model,
        View::Top);

    std::cout << '\n';

    renderer.render(
        model,
        View::Side);
}


// ============================================================
// ROUTING
// ============================================================

bool routeAndAddWire(
    Router& router,
    RouteModel& model,
    char name,
    const std::string& netName,
    NetType netType,
    FactorioWire factorioWire,
    Point start,
    Point end)
{
    Path path =
        router.findPath(
            start,
            end);

    if (!path.found())
    {
        std::cout
            << "Wire "
            << name
            << " not found.\n";

        return false;
    }

    router.commitPath(path);

    model.addWire(
        Wire{
            name,
            netName,
            netType,
            factorioWire,
            path,
            buildSegments(path)
        });

    return true;
}


bool createNewRoute(
    RouteModel& model)
{
    constexpr int WIDTH = 14;
    constexpr int HEIGHT = 10;
    constexpr int LAYERS = 2;

    constexpr int TURN_PENALTY = 3;

    constexpr int LAYER_CHANGE_PENALTY =
        2;

    constexpr int UPPER_LAYER_STEP_PENALTY =
        1;

    Router router(
        WIDTH,
        HEIGHT,
        LAYERS,
        TURN_PENALTY,
        LAYER_CHANGE_PENALTY,
        UPPER_LAYER_STEP_PENALTY);

    model =
        RouteModel{
            WIDTH,
            HEIGHT,
            LAYERS,
            {}
        };

    // --------------------------------------------------------
    // WIRE A
    // VDD = Factorio Red Wire
    // --------------------------------------------------------

    if (!routeAndAddWire(
            router,
            model,
            'A',
            "VDD",
            NetType::VDD,
            FactorioWire::Red,
            Point{2, 4, 0},
            Point{11, 4, 0}))
    {
        return false;
    }

    // --------------------------------------------------------
    // WIRE B
    // VSS = Factorio Green Wire
    // --------------------------------------------------------

    if (!routeAndAddWire(
            router,
            model,
            'B',
            "VSS",
            NetType::VSS,
            FactorioWire::Green,
            Point{6, 1, 0},
            Point{6, 8, 0}))
    {
        return false;
    }

    return true;
}


// ============================================================
// JSON LOAD
// ============================================================

bool openRouteFile(
    const std::string& inputFilename)
{
    const std::string filename =
        normalizeRouteFilename(
            inputFilename);

    if (filename.empty())
    {
        std::cerr
            << "Unsupported file extension.\n"
            << "Only .json is supported.\n";

        return false;
    }

    RouteModel model;

    std::string error;

    if (!loadRoute(
            filename,
            model,
            error))
    {
        std::cerr
            << "LOAD ERROR: "
            << error
            << '\n';

        return false;
    }

    std::cout
        << "Loaded: "
        << filename
        << "\n\n";

    // Zadny Router.
    // Zadny findPath().
    // Jen zobrazime ulozeny model.

    showModel(model);

    return true;
}


// ============================================================
// JSON SAVE
// ============================================================

void saveModelInteractive(
    const RouteModel& model)
{
    std::string input;

    std::cout
        << "\nSave filename"
        << " [route.json]: ";

    std::getline(
        std::cin,
        input);

    const std::string filename =
        normalizeRouteFilename(
            input);

    if (filename.empty())
    {
        std::cerr
            << "Unsupported file extension.\n"
            << "Only .json is supported.\n";

        return;
    }

    std::string error;

    if (!saveRoute(
            model,
            filename,
            error))
    {
        std::cerr
            << "SAVE ERROR: "
            << error
            << '\n';

        return;
    }

    std::cout
        << "Saved: "
        << filename
        << '\n';
}


// ============================================================
// QUICK BLENDER TEST
// ============================================================

void exportBlenderTest(
    const RouteModel& model)
{
    std::string error;

    if (!exportObj(
            model,
            "route.obj",
            error))
    {
        std::cerr
            << "OBJ EXPORT ERROR: "
            << error
            << '\n';

        return;
    }

    std::cout
        << "\nBlender export created:\n"
        << "  route.obj\n"
        << "  route.mtl\n";
}


// ============================================================
// HELP
// ============================================================

void printHelp()
{
    std::cout
        << "Manhattan Router\n\n"

        << "Usage:\n\n"

        << "  router12.exe\n"
        << "      Interactive menu.\n\n"

        << "  router12.exe route\n"
        << "      Opens route.json without rerouting.\n\n"

        << "  router12.exe route.json\n"
        << "      Opens route.json without rerouting.\n\n"

        << "  router12.exe -route\n"
        << "      Same as route.json.\n\n"

        << "  router12.exe --open route.json\n"
        << "      Opens route.json.\n";
}


// ============================================================
// MAIN
// ============================================================

int main(
    int argc,
    char* argv[])
{
    // ========================================================
    // COMMAND LINE MODE
    // ========================================================

    if (argc > 1)
    {
        std::string argument =
            argv[1];

        if (argument == "--help" ||
            argument == "-h")
        {
            printHelp();

            return 0;
        }

        if (argument == "--open" ||
            argument == "-o")
        {
            if (argc < 3)
            {
                std::cerr
                    << "Missing filename.\n";

                return 1;
            }

            return
                openRouteFile(
                    argv[2])
                ? 0
                : 1;
        }

        // Podpora:
        //
        // router12.exe -route

        if (argument.size() > 1 &&
            argument.front() == '-')
        {
            argument.erase(
                argument.begin());
        }

        return
            openRouteFile(
                argument)
            ? 0
            : 1;
    }

    // ========================================================
    // INTERACTIVE MODE
    // ========================================================

    while (true)
    {
        std::cout
            << "\n"
            << "=== MANHATTAN ROUTER ===\n"
            << '\n'
            << "1 - New route\n"
            << "2 - Open route\n"
            << "3 - Exit\n"
            << '\n'
            << "> ";

        std::string choice;

        std::getline(
            std::cin,
            choice);

        // ----------------------------------------------------
        // NEW ROUTE
        // ----------------------------------------------------

        if (choice == "1")
        {
            RouteModel model;

            if (!createNewRoute(model))
            {
                std::cerr
                    << "Routing failed.\n";

                continue;
            }

            std::cout
                << "\nRoute calculated.\n\n";

            showModel(model);

            // ================================================
            // QUICK TEST:
            // AUTOMATICKY VYROB OBJ + MTL PRO BLENDER
            // ================================================

            exportBlenderTest(model);

            // ------------------------------------------------
            // JSON SAVE
            // ------------------------------------------------

            std::cout
                << "\nSave route? [Y/n]: ";

            std::string saveChoice;

            std::getline(
                std::cin,
                saveChoice);

            if (saveChoice.empty() ||
                saveChoice == "y" ||
                saveChoice == "Y")
            {
                saveModelInteractive(
                    model);
            }
        }

        // ----------------------------------------------------
        // OPEN ROUTE
        // ----------------------------------------------------

        else if (choice == "2")
        {
            std::string filename;

            std::cout
                << "Filename: ";

            std::getline(
                std::cin,
                filename);

            if (!filename.empty())
            {
                openRouteFile(
                    filename);
            }
        }

        // ----------------------------------------------------
        // EXIT
        // ----------------------------------------------------

        else if (choice == "3")
        {
            return 0;
        }

        else
        {
            std::cout
                << "Unknown option.\n";
        }
    }
}