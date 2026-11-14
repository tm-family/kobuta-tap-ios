#!/usr/bin/env python3
"""傘のきせかえ（課金）の絵を書き出す。

こぶたと着ぐるみのおおかみの絵は、葉っぱの傘を絵の中に直接描いている。
その傘（葉っぱの形の部分と葉脈）だけを、きせかえの傘の柄に差し替えた絵を、アセットカタログに書き出す。
傘の形（輪郭）と持ち手は葉っぱの傘と同じなので、大きさ・揺れの支点・当たり判定は変わらない。

    python3 Tools/generate_umbrella_skins.py          # 書き出す
    python3 Tools/generate_umbrella_skins.py --check  # 書き出したものが最新か確かめる（違えば 1 で終わる）

書き出すもの（<skin> は UmbrellaSkin の rawValue）:

- KobutaAssets.xcassets/UmbrellaSkins/<キャラクター>_<状態>_<skin>.imageset … こぶた・着ぐるみのおおかみの、傘をさしている絵
- KobutaAssets.xcassets/UmbrellaSkins/umbrella_<skin>.imageset … 着地して落とす傘と、きせかえ画面の見本

柄を変えるときは、このファイルの SKINS を書き換えて実行し、書き出した絵もコミットする。
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "KobutaTap" / "KobutaAssets.xcassets"
OUTPUT = ASSETS / "UmbrellaSkins"

#: 葉っぱの傘の部分（絵の中の 2 つの path）。キャラクターの絵と umbrella_leaf の両方に、この形で入っている
LEAF_CANOPY = '<path d="M36 74 Q100 8 164 74 Q148 64 132 74 Q116 62 100 74 Q84 62 68 74 Q52 64 36 74 Z" fill="#8CC97E"/>'
LEAF_VEINS = ('<path d="M100 70 L100 30 M100 52 Q86 42 74 44 M100 52 Q114 42 126 44" fill="none" '
              'stroke="#B5DDAA" stroke-width="3" stroke-linecap="round"/>')
CANOPY_SHAPE = "M36 74 Q100 8 164 74 Q148 64 132 74 Q116 62 100 74 Q84 62 68 74 Q52 64 36 74 Z"

#: 傘をさしている絵（座った絵は傘を落としているので要らない）
CHARACTERS = [
    "piglet_normal", "piglet_tapped", "piglet_run",
    "disguise_normal", "disguise_hard", "disguise_tapped", "disguise_run",
]


def ribs(color: str) -> str:
    """傘の骨（てっぺんから縁へ）と、てっぺんの石突き。"""
    return (f'<path d="M100 42 Q82 52 68 72 M100 42 L100 72 M100 42 Q118 52 132 72" fill="none" '
            f'stroke="{color}" stroke-width="2" stroke-linecap="round"/>'
            f'<path d="M100 42 L100 33" stroke="#6B4A2E" stroke-width="3" stroke-linecap="round"/>'
            f'<circle cx="100" cy="32" r="2.6" fill="#6B4A2E"/>')


def canopy(fill: str) -> str:
    return f'<path d="{CANOPY_SHAPE}" fill="{fill}"/>'


def flower(cx: float, cy: float, radius: float, petal: str, center: str, petals: int = 5,
           petal_ratio: float = 0.55, rotation: float = -90) -> str:
    """花びらを円く並べた花（桜・ひまわり）。"""
    parts = []
    for index in range(petals):
        angle = math.radians(rotation + 360 * index / petals)
        x, y = cx + radius * 0.55 * math.cos(angle), cy + radius * 0.55 * math.sin(angle)
        parts.append(f'<ellipse cx="{x:.2f}" cy="{y:.2f}" rx="{radius * petal_ratio:.2f}" ry="{radius * 0.32:.2f}" '
                     f'transform="rotate({math.degrees(angle):.1f} {x:.2f} {y:.2f})" fill="{petal}"/>')
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{radius * 0.3:.2f}" fill="{center}"/>')
    return "".join(parts)


def maple_leaf(cx: float, cy: float, size: float, color: str, rotation: float = 0) -> str:
    """紅葉（7 つにとがった葉と、短い柄）。"""
    points = []
    lobes = [(-90, 1.0), (-38, 0.86), (8, 0.62), (52, 0.42), (128, 0.42), (172, 0.62), (218, 0.86)]
    for angle, length in lobes:
        tip = math.radians(angle)
        points.append((math.cos(tip) * size * length, math.sin(tip) * size * length))
        notch = math.radians(angle + 23)
        points.append((math.cos(notch) * size * 0.32, math.sin(notch) * size * 0.32))
    path = "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in points) + " Z"
    stem = f"M0 {size * 0.2:.2f} L0 {size * 0.75:.2f}"
    return (f'<g transform="translate({cx} {cy}) rotate({rotation})">'
            f'<path d="{path}" fill="{color}"/>'
            f'<path d="{stem}" stroke="{color}" stroke-width="1.4" stroke-linecap="round"/></g>')


def snowflake(cx: float, cy: float, size: float, color: str) -> str:
    """雪の結晶（6 本の腕と、腕の先の小さな枝）。"""
    lines = []
    for index in range(6):
        angle = math.radians(60 * index - 90)
        x, y = cx + size * math.cos(angle), cy + size * math.sin(angle)
        lines.append(f"M{cx} {cy} L{x:.2f} {y:.2f}")
        bx, by = cx + size * 0.6 * math.cos(angle), cy + size * 0.6 * math.sin(angle)
        for side in (-1, 1):
            branch = angle + side * math.radians(40)
            lines.append(f"M{bx:.2f} {by:.2f} L{bx + size * 0.32 * math.cos(branch):.2f} "
                         f"{by + size * 0.32 * math.sin(branch):.2f}")
    width = max(1.2, size * 0.18)
    return f'<path d="{" ".join(lines)}" fill="none" stroke="{color}" stroke-width="{width:.2f}" stroke-linecap="round"/>'


def dots(points: list[tuple[float, float, float]], color: str) -> str:
    return "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}"/>' for x, y, r in points)


#: きせかえの傘。キーは UmbrellaSkin の rawValue。飾りは傘の内側（縁から少し離した所）に置く
SKINS: dict[str, str] = {
    "sakura": canopy("#F6B3C6") + ribs("#FAD3DF")
    + flower(100, 57, 10, "#FFFFFF", "#F07A9A") + flower(77, 62, 7, "#FFFFFF", "#F07A9A", rotation=-60)
    + flower(123, 62, 7, "#FFFFFF", "#F07A9A", rotation=-120)
    + dots([(88, 67, 1.4), (112, 67, 1.4)], "#FFFFFF"),
    "sunflower": canopy("#FFD34E") + ribs("#FFE69A")
    + flower(100, 57, 11, "#F59A23", "#7A4A24", petals=10, petal_ratio=0.5)
    + flower(74, 63, 7, "#F59A23", "#7A4A24", petals=8, petal_ratio=0.5)
    + flower(126, 63, 7, "#F59A23", "#7A4A24", petals=8, petal_ratio=0.5),
    "momiji": canopy("#F6A85B") + ribs("#F9C894")
    + maple_leaf(100, 57, 10, "#D9433B") + maple_leaf(76, 63, 7, "#E8613A", rotation=-20)
    + maple_leaf(124, 63, 7, "#C9342F", rotation=18),
    "snow": canopy("#86C5EC") + ribs("#B8DDF5")
    + snowflake(100, 57, 9.5, "#FFFFFF") + snowflake(75, 63, 6, "#FFFFFF") + snowflake(125, 63, 6, "#FFFFFF")
    + dots([(88, 46, 1.3), (112, 46, 1.3), (62, 67, 1.2), (138, 67, 1.2)], "#FFFFFF"),
    "polkadot": canopy("#F2707F") + ribs("#F7A3AD")
    + dots([(100, 50, 3.6), (84, 57, 3.2), (116, 57, 3.2), (68, 64, 2.8), (132, 64, 2.8),
            (100, 65, 3.2), (90, 46, 1.9), (110, 46, 1.9), (58, 63, 2.0), (142, 63, 2.0)], "#FFFFFF"),
}

#: 落とす傘の見本（umbrella_leaf と同じ枠。持ち手はまっすぐ下）
UMBRELLA_FRAME = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="30 0 140 120" width="140" height="120">'
                  '<path d="M100 74 L100 116" stroke="#6B4A2E" stroke-width="5" stroke-linecap="round"/>{canopy}</svg>')


def imageset_contents(svg_name: str) -> str:
    return json.dumps({
        "images": [{"filename": svg_name, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    }, indent=2)


def outputs() -> dict[Path, str]:
    """書き出すファイルと中身。"""
    files: dict[Path, str] = {}
    files[OUTPUT / "Contents.json"] = json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2)
    for skin, markup in SKINS.items():
        for character in CHARACTERS:
            source = (ASSETS / "Characters" / f"{character}.imageset" / f"{character}.svg").read_text()
            if source.count(LEAF_CANOPY) != 1 or source.count(LEAF_VEINS) != 1:
                raise SystemExit(f"{character}.svg に葉っぱの傘が見つかりません（絵を変えたら LEAF_CANOPY / LEAF_VEINS も直す）")
            svg = source.replace(LEAF_CANOPY + LEAF_VEINS, markup) if LEAF_CANOPY + LEAF_VEINS in source else \
                source.replace(LEAF_VEINS, "").replace(LEAF_CANOPY, markup)
            name = f"{character}_{skin}"
            files[OUTPUT / f"{name}.imageset" / f"{name}.svg"] = svg
            files[OUTPUT / f"{name}.imageset" / "Contents.json"] = imageset_contents(f"{name}.svg")
        name = f"umbrella_{skin}"
        files[OUTPUT / f"{name}.imageset" / f"{name}.svg"] = UMBRELLA_FRAME.format(canopy=markup)
        files[OUTPUT / f"{name}.imageset" / "Contents.json"] = imageset_contents(f"{name}.svg")
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="書き出したものが最新か確かめる")
    args = parser.parse_args()

    files = outputs()
    stale = [path for path, content in files.items() if not path.exists() or path.read_text() != content]
    if args.check:
        for path in stale:
            print(f"古いか、ありません: {path.relative_to(ROOT)}")
        if stale:
            print("python3 Tools/generate_umbrella_skins.py を実行して、書き出した絵をコミットしてください")
            return 1
        print(f"最新: {len(files)} ファイル")
        return 0
    for path in stale:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content := files[path])
    print(f"書き出し: {len(stale)} ファイル（全 {len(files)} ファイル）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
