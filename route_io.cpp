#include "route_io.hpp"
#include "segment.hpp"

#include <nlohmann/json.hpp>

#include <fstream>
#include <stdexcept>
#include <string>
#include <utility>

using json = nlohmann::json;

namespace
{
    const char* netTypeToString(NetType type)
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

    NetType netTypeFromString(
        const std::string& value)
    {
        if (value == "SIGNAL")
            return NetType::Signal;

        if (value == "VDD")
            return NetType::VDD;

        if (value == "VSS")
            return NetType::VSS;

        throw std::runtime_error(
            "Unknown NetType: " + value);
    }

    const char* factorioWireToString(
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

    FactorioWire factorioWireFromString(
        const std::string& value)
    {
        if (value == "NONE")
            return FactorioWire::None;

        if (value == "RW")
            return FactorioWire::Red;

        if (value == "GW")
            return FactorioWire::Green;

        throw std::runtime_error(
            "Unknown FactorioWire: " + value);
    }
}

bool saveRoute(
    const RouteModel& model,
    const std::string& filename,
    std::string& error)
{
    try
    {
        json root;

        root["format"] =
            "ManhattanRouter";

        root["version"] = 1;

        root["grid"] =
        {
            {"width", model.width},
            {"height", model.height},
            {"layers", model.layers}
        };

        root["wires"] =
            json::array();

        for (const Wire& wire : model.wires)
        {
            json points =
                json::array();

            for (const Point& p :
                 wire.path.points)
            {
                points.push_back(
                {
                    p.x,
                    p.y,
                    p.z
                });
            }

            json wireJson;

            wireJson["name"] =
                std::string(
                    1,
                    wire.name);

            wireJson["netName"] =
                wire.netName;

            wireJson["netType"] =
                netTypeToString(
                    wire.netType);

            wireJson["factorioWire"] =
                factorioWireToString(
                    wire.factorioWire);

            wireJson["path"] =
            {
                {
                    "totalCost",
                    wire.path.totalCost
                },
                {
                    "turns",
                    wire.path.turns
                },
                {
                    "layerChanges",
                    wire.path.layerChanges
                },
                {
                    "points",
                    points
                }
            };

            root["wires"].push_back(
                wireJson);
        }

        std::ofstream file(filename);

        if (!file)
        {
            error =
                "Cannot create file: "
                + filename;

            return false;
        }

        file
            << root.dump(4)
            << '\n';

        return true;
    }
    catch (const std::exception& e)
    {
        error = e.what();

        return false;
    }
}

bool loadRoute(
    const std::string& filename,
    RouteModel& model,
    std::string& error)
{
    try
    {
        std::ifstream file(filename);

        if (!file)
        {
            error =
                "Cannot open file: "
                + filename;

            return false;
        }

        json root;

        file >> root;

        if (root.at("format")
                .get<std::string>()
            != "ManhattanRouter")
        {
            throw std::runtime_error(
                "Unsupported file format.");
        }

        const int version =
            root.at("version")
                .get<int>();

        if (version != 1)
        {
            throw std::runtime_error(
                "Unsupported file version.");
        }

        RouteModel loadedModel;

        loadedModel.width =
            root.at("grid")
                .at("width")
                .get<int>();

        loadedModel.height =
            root.at("grid")
                .at("height")
                .get<int>();

        loadedModel.layers =
            root.at("grid")
                .at("layers")
                .get<int>();

        if (loadedModel.width <= 0 ||
            loadedModel.height <= 0 ||
            loadedModel.layers <= 0)
        {
            throw std::runtime_error(
                "Invalid grid dimensions.");
        }

        for (const json& wireJson :
             root.at("wires"))
        {
            Wire wire;

            const std::string name =
                wireJson.at("name")
                    .get<std::string>();

            if (name.empty())
            {
                throw std::runtime_error(
                    "Wire has empty name.");
            }

            wire.name =
                name.front();

            wire.netName =
                wireJson.at("netName")
                    .get<std::string>();

            wire.netType =
                netTypeFromString(
                    wireJson.at("netType")
                        .get<std::string>());

            wire.factorioWire =
                factorioWireFromString(
                    wireJson.at("factorioWire")
                        .get<std::string>());

            const json& pathJson =
                wireJson.at("path");

            wire.path.totalCost =
                pathJson.at("totalCost")
                    .get<int>();

            wire.path.turns =
                pathJson.at("turns")
                    .get<int>();

            wire.path.layerChanges =
                pathJson.at("layerChanges")
                    .get<int>();

            for (const json& pointJson :
                 pathJson.at("points"))
            {
                if (!pointJson.is_array() ||
                    pointJson.size() != 3)
                {
                    throw std::runtime_error(
                        "Invalid point.");
                }

                wire.path.points.push_back(
                    Point{
                        pointJson.at(0)
                            .get<int>(),

                        pointJson.at(1)
                            .get<int>(),

                        pointJson.at(2)
                            .get<int>()
                    });
            }

            wire.segments =
                buildSegments(
                    wire.path);

            loadedModel.addWire(
                wire);
        }

        model =
            std::move(
                loadedModel);

        return true;
    }
    catch (const std::exception& e)
    {
        error = e.what();

        return false;
    }
}