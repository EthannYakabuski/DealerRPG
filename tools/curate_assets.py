"""Audit supplied Kenney GLBs and curate the browser game's runtime library.

Run with Python 3. No third-party packages are required. Original assets remain
untouched. Pack directories preserve their separate external palette textures.
"""
from __future__ import annotations

import itertools
import json
import shutil
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Assets"
DEST = ROOT / "art" / "models"

SELECTION = {
    "Characters": [f"character-{gender}-{letter}" for gender in ("male", "female") for letter in "abcdef"],
    "Commercial_City": [f"building-{letter}" for letter in "abcdefghijkln"] + ["detail-awning", "detail-parasol-a"],
    "Suburban_City": [f"building-type-{letter}" for letter in "abcdefghijklmnopqrs"] + ["fence", "fence-low", "planter", "tree-large", "tree-small"],
    "Industrial_City": ["building-a", "building-b", "building-c", "building-d", "building-g", "shipping-container-a", "solar-panel-flat", "solar-panel-landscape-group"],
    "Cars": ["sedan", "sedan-sports", "suv", "hatchback-sports", "van", "delivery", "taxi", "police", "ambulance"],
    "Roads": ["light-curved", "light-square", "road-sign-stop", "road-sign-street", "traffic-light", "dumpster", "construction-cone", "construction-barrier", "electricity-pole"],
    "Skateboard": ["skateboard", "rail-low", "rail-high", "half-pipe", "obstacle-box", "steps"],
    "Furniture": ["bedSingle", "cabinetBed", "desk", "chairDesk", "chair", "table", "tableRound", "laptop", "computerScreen", "computerKeyboard", "loungeSofa", "loungeChair", "tableCoffee", "kitchenFridge", "kitchenStove", "kitchenSink", "kitchenCabinet", "kitchenCoffeeMachine", "kitchenMicrowave", "bookcaseOpen", "books", "pottedPlant", "plantSmall1", "lampRoundFloor", "rugRectangle", "toilet", "bathroomSink", "shower", "televisionModern", "speaker", "bench", "trashcan", "coatRackStanding", "cardboardBoxClosed"],
    "Market": ["cash-register", "display-bread", "display-fruit", "freezer", "freezers-standing", "shelf-bags", "shelf-boxes", "shelf-end", "shopping-basket", "shopping-cart", "character-employee"],
    "Nature": ["tree_default", "tree_default_fall", "tree_oak", "tree_oak_fall", "tree_pineRoundA", "tree_small", "plant_bush", "plant_bushSmall", "rock_smallA", "flower_yellowA", "flower_redA"],
    "MoreNature": ["tree-autumn", "tree-autumn-tall", "rock-a", "box", "barrel"],
    "Blasters": ["blaster-a", "blaster-b", "crate-small", "crate-medium"],
}


def glb_json(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"Not a GLB: {path}")
    length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError(f"No JSON chunk: {path}")
    return json.loads(data[20 : 20 + length])


def transform(point, node):
    if "matrix" in node:
        m = node["matrix"]
        return [sum(m[col * 4 + row] * point[col] for col in range(3)) + m[12 + row] for row in range(3)]
    p = [point[i] * node.get("scale", [1, 1, 1])[i] for i in range(3)]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    # Quaternion vector rotation.
    uv = [y*p[2]-z*p[1], z*p[0]-x*p[2], x*p[1]-y*p[0]]
    uuv = [y*uv[2]-z*uv[1], z*uv[0]-x*uv[2], x*uv[1]-y*uv[0]]
    t = node.get("translation", [0, 0, 0])
    return [p[i] + 2*(w*uv[i]+uuv[i]) + t[i] for i in range(3)]


def metadata(path: Path) -> dict:
    doc = glb_json(path)
    low, high = [float("inf")]*3, [float("-inf")]*3
    triangles = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            triangles += doc["accessors"][prim.get("indices", prim["attributes"]["POSITION"])]["count"] // 3
    def walk(index, ancestors):
        node = doc["nodes"][index]
        chain = [node] + ancestors
        if "mesh" in node:
            for prim in doc["meshes"][node["mesh"]]["primitives"]:
                acc = doc["accessors"][prim["attributes"]["POSITION"]]
                if "min" not in acc or "max" not in acc:
                    continue
                for corner in itertools.product(*zip(acc["min"], acc["max"])):
                    point = list(corner)
                    for ancestor in chain:
                        point = transform(point, ancestor)
                    for i in range(3):
                        low[i] = min(low[i], point[i])
                        high[i] = max(high[i], point[i])
        for child in node.get("children", []):
            walk(child, chain)
    for root_index in doc.get("scenes", [{}])[doc.get("scene", 0)].get("nodes", []):
        walk(root_index, [])
    if low[0] == float("inf"):
        low, high = [0,0,0], [1,1,1]
    return {
        "source": path.relative_to(ROOT).as_posix(),
        "bytes": path.stat().st_size,
        "min": [round(n, 5) for n in low],
        "max": [round(n, 5) for n in high],
        "size": [round(high[i]-low[i], 5) for i in range(3)],
        "triangles": triangles,
        "meshes": len(doc.get("meshes", [])),
        "materials": len(doc.get("materials", [])),
        "animations": [a.get("name", "unnamed") for a in doc.get("animations", [])],
        "external_images": [i["uri"] for i in doc.get("images", []) if "uri" in i and not i["uri"].startswith("data:")],
        "skinned": bool(doc.get("skins")),
    }


def main():
    catalog = {}
    for path in sorted(SOURCE.rglob("*.glb")):
        key = f"{path.relative_to(SOURCE).parts[0]}/{path.stem}"
        catalog[key] = metadata(path)
    manifest = {}
    for pack, names in SELECTION.items():
        for name in names:
            key = f"{pack}/{name}"
            record = catalog[key]
            source = ROOT / record["source"]
            destination = DEST / pack / source.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            for uri in record["external_images"]:
                image_target = destination.parent / uri
                image_target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source.parent / uri, image_target)
            manifest[key] = dict(record, path="res://" + destination.relative_to(ROOT).as_posix())
        license_path = SOURCE / pack / "License.txt"
        if license_path.exists():
            shutil.copy2(license_path, DEST / pack / "LICENSE.txt")
    docs = ROOT / "docs"
    docs.mkdir(exist_ok=True)
    (docs / "asset_catalog.json").write_text(json.dumps(catalog, indent=2), encoding="utf-8")
    (ROOT / "art" / "asset_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Audited {len(catalog)} GLBs; curated {len(manifest)} models ({sum(r['bytes'] for r in manifest.values())/1048576:.2f} MiB before textures/import).")
    for key in ["Characters/character-male-f", "Characters/character-male-c", "Cars/sedan", "Commercial_City/building-a", "Suburban_City/building-type-a", "Furniture/bedSingle", "Skateboard/skateboard"]:
        print(key, manifest[key]["size"], manifest[key]["triangles"])


if __name__ == "__main__":
    main()
