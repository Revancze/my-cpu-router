#include "obj_exporter.hpp"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <string>

namespace
{
constexpr double WIRE_THICKNESS = 0.20;

std::string safeName(
    std::string text)
{
    for (char& c : text)
    {
        const unsigned char uc = static_cast<unsigned char>(c);

        if (!std::isalnum(uc) && c != '_')
        {
            c = '_';
        }
    }

    return text;
}

const char* materialName(
    FactorioWire wire)
{
    switch (wire)
    {
    case FactorioWire::Red:
        return "RW";

    case FactorioWire::Green:
        return "GW";

    case FactorioWire::None:
        return "SIGNAL";
    }

    return "SIGNAL";
}

void writeMaterialFile(
    const std::filesystem::path& path)
{
    std::ofstream file(path);

    // VDD / Red Wire
    file << "newmtl RW\n"
         << "Kd 0.80 0.05 0.05\n"
         << "Ka 0.10 0.01 0.01\n\n";

    // VSS / Green Wire
    file << "newmtl GW\n"
         << "Kd 0.05 0.70 0.10\n"
         << "Ka 0.01 0.10 0.01\n\n";

    // Ostatni signal
    file << "newmtl SIGNAL\n"
         << "Kd 0.70 0.70 0.70\n"
         << "Ka 0.10 0.10 0.10\n\n";
}

void writeBox(
    std::ofstream& file,
    const Segment& segment,
    std::size_t& vertexBase)
{
    const double half = WIRE_THICKNESS / 2.0;

    double minX = std::min(segment.start.x, segment.end.x);

    double maxX = std::max(segment.start.x, segment.end.x);

    double minY = std::min(segment.start.y, segment.end.y);

    double maxY = std::max(segment.start.y, segment.end.y);

    double minZ = std::min(segment.start.z, segment.end.z);

    double maxZ = std::max(segment.start.z, segment.end.z);

    // Rozsirime aktivni osu i konce,
    // aby na sebe segmenty pekne navazovaly.

    if (segment.start.x == segment.end.x)
    {
        minX -= half;
        maxX += half;
    }
    else
    {
        minX -= half;
        maxX += half;
    }

    if (segment.start.y == segment.end.y)
    {
        minY -= half;
        maxY += half;
    }
    else
    {
        minY -= half;
        maxY += half;
    }

    if (segment.start.z == segment.end.z)
    {
        minZ -= half;
        maxZ += half;
    }
    else
    {
        minZ -= half;
        maxZ += half;
    }

    // 8 vrcholu kvadru.

    file << "v " << minX << ' ' << minY << ' ' << minZ << '\n';

    file << "v " << maxX << ' ' << minY << ' ' << minZ << '\n';

    file << "v " << maxX << ' ' << maxY << ' ' << minZ << '\n';

    file << "v " << minX << ' ' << maxY << ' ' << minZ << '\n';

    file << "v " << minX << ' ' << minY << ' ' << maxZ << '\n';

    file << "v " << maxX << ' ' << minY << ' ' << maxZ << '\n';

    file << "v " << maxX << ' ' << maxY << ' ' << maxZ << '\n';

    file << "v " << minX << ' ' << maxY << ' ' << maxZ << '\n';

    const std::size_t a = vertexBase + 1;
    const std::size_t b = vertexBase + 2;
    const std::size_t c = vertexBase + 3;
    const std::size_t d = vertexBase + 4;

    const std::size_t e = vertexBase + 5;
    const std::size_t f = vertexBase + 6;
    const std::size_t g = vertexBase + 7;
    const std::size_t h = vertexBase + 8;

    file << "f " << a << ' ' << b << ' ' << c << ' ' << d << '\n';

    file << "f " << e << ' ' << h << ' ' << g << ' ' << f << '\n';

    file << "f " << a << ' ' << e << ' ' << f << ' ' << b << '\n';

    file << "f " << b << ' ' << f << ' ' << g << ' ' << c << '\n';

    file << "f " << c << ' ' << g << ' ' << h << ' ' << d << '\n';

    file << "f " << e << ' ' << a << ' ' << d << ' ' << h << '\n';

    vertexBase += 8;
}
} // namespace

bool exportObj(
    const RouteModel& model,
    const std::string& filename,
    std::string& error)
{
    try
    {
        std::filesystem::path objPath(filename);

        if (!objPath.has_extension())
        {
            objPath += ".obj";
        }

        if (objPath.extension() != ".obj")
        {
            error = "OBJ exporter requires .obj file.";

            return false;
        }

        std::filesystem::path mtlPath = objPath;

        mtlPath.replace_extension(".mtl");

        std::ofstream file(objPath);

        if (!file)
        {
            error = "Cannot create OBJ file: " + objPath.string();

            return false;
        }

        writeMaterialFile(mtlPath);

        file << "# Manhattan Router OBJ Export\n"
             << "# Grid: " << model.width << " x " << model.height << " x "
             << model.layers << "\n\n";

        file << "mtllib " << mtlPath.filename().string() << "\n\n";

        std::size_t vertexBase = 0;

        for (const Wire& wire : model.wires)
        {
            file << "o wire_" << wire.name << "_" << safeName(wire.netName)
                 << '\n';

            file << "usemtl " << materialName(wire.factorioWire) << '\n';

            for (const Segment& segment : wire.segments)
            {
                writeBox(file, segment, vertexBase);
            }

            file << '\n';
        }

        return true;
    }
    catch (const std::exception& e)
    {
        error = e.what();

        return false;
    }
}
