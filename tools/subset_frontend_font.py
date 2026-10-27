#!/usr/bin/env python3
"""Build the independent frontend font without changing the walking HUD font.

Optional build dependency: fonttools. The generated font is committed; players
need neither Python nor the original font. Example:
python3 tools/subset_frontend_font.py \
    --font /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
"""

import argparse
from pathlib import Path


def main():
    from fontTools import subset

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sources = sorted((root / "scripts/frontend").rglob("*.gd"))
    sources += sorted((root / "scenes/frontend").rglob("*.tscn"))
    test = root / "tools/test_frontend.gd"
    if test.exists():
        sources.append(test)
    text = "".join(source.read_text(encoding="utf-8") for source in sources)
    text += "".join(chr(codepoint) for codepoint in range(32, 127))
    options = subset.Options()
    options.font_number = 0
    options.layout_features = ["*"]
    font = subset.load_font(str(args.font), options)
    worker = subset.Subsetter(options=options)
    worker.populate(text=text)
    worker.subset(font)
    for name_id, value in {
        1: "Selesia Frontend UI Subset",
        2: "Regular",
        3: "SelesiaFrontendUISubset-Regular",
        4: "Selesia Frontend UI Subset Regular",
        6: "SelesiaFrontendUISubset-Regular",
        16: "Selesia Frontend UI Subset",
        17: "Regular",
    }.items():
        font["name"].setName(value, name_id, 3, 1, 0x409)
    output = root / "assets/frontend/ui.otf"
    output.parent.mkdir(parents=True, exist_ok=True)
    subset.save_font(font, str(output), options)
    print(f"{output}: {output.stat().st_size:,} bytes; {len(set(text))} characters")


if __name__ == "__main__":
    main()
