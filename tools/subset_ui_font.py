#!/usr/bin/env python3
"""Optional font maintenance: subset an OFL Noto CJK font to the project's text.

The already-built font is committed; running the game needs no Python packages.
To rebuild: python3 -m pip install fonttools
python3 tools/subset_ui_font.py --font /path/to/NotoSansCJK-Regular.ttc
"""
import argparse
from pathlib import Path


def main():
    from fontTools import subset

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    text = "".join(p.read_text(encoding="utf-8") for p in (root / "scripts").rglob("*.gd"))
    text += "".join(chr(n) for n in range(32, 127))
    options = subset.Options()
    options.font_number = 0
    options.layout_features = ["*"]
    font = subset.load_font(str(args.font), options)
    worker = subset.Subsetter(options=options)
    worker.populate(text=text)
    worker.subset(font)
    # Use a new family name for the modified font; keep copyright/license names.
    for name_id, value in {
        1: "Selesia UI Subset", 2: "Regular", 3: "SelesiaUISubset-Regular",
        4: "Selesia UI Subset Regular", 6: "SelesiaUISubset-Regular",
        16: "Selesia UI Subset", 17: "Regular",
    }.items():
        font["name"].setName(value, name_id, 3, 1, 0x409)
    output = root / "assets/fonts/ui.otf"
    subset.save_font(font, str(output), options)
    print(f"{output}: {output.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
