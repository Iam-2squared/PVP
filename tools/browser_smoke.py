#!/usr/bin/env python3
"""Exercise a local Godot Web export in desktop and landscape touch Chromium.

Optional development dependencies: playwright, Pillow; an installed Chromium.
Start tools/serve_preview.py first, then run this file. Real device FPS is not
inferred from Chromium's software WebGL renderer.
"""
import argparse
import asyncio
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import statistics

from playwright.async_api import async_playwright


FATAL = re.compile(
    r"SCRIPT ERROR|Parse Error|Failed to load script|RuntimeError|Aborted\(|"
    r"WebGL[^\n]*(?:not supported|unsupported|failed to create)", re.IGNORECASE
)


def image_signature(data):
    from PIL import Image

    image = Image.open(io.BytesIO(data)).convert("RGB")
    width, height = image.size
    # Inspect central world pixels; the HUD itself cannot satisfy this check.
    pixels = bytearray()
    for y in range(int(height * 0.3), int(height * 0.65), 3):
        for x in range(int(width * 0.3), int(width * 0.7), 3):
            pixels.extend(image.getpixel((x, y)))
    spread = sum(statistics.pstdev(pixels[channel::3]) for channel in range(3))
    if spread < 15:
        raise AssertionError(f"Canvas appears blank: RGB standard deviation={spread:.2f}")
    return hashlib.sha256(pixels).hexdigest(), round(spread, 2)


async def touch(cdp, event_type, points):
    await cdp.send("Input.dispatchTouchEvent", {
        "type": event_type,
        "touchPoints": [{"x": x, "y": y, "id": touch_id, "radiusX": 1,
                         "radiusY": 1, "force": 1} for touch_id, x, y in points],
    })


async def check_profile(browser, args, name, width, height, mobile):
    output = args.output
    context = await browser.new_context(
        viewport={"width": width, "height": height},
        device_scale_factor=1,
        has_touch=mobile,
        is_mobile=mobile,
    )
    page = await context.new_page()
    ready = asyncio.Event()
    logs = []
    fatal = []
    console_errors = []

    def on_console(message):
        text = message.text
        logs.append(text)
        if "VOXEL_WORLD_READY" in text:
            ready.set()
        if message.type == "error":
            console_errors.append(text)
        if FATAL.search(text):
            fatal.append(text)

    page.on("console", on_console)
    page.on("pageerror", lambda error: fatal.append(str(error)))
    response = await page.goto(args.url, wait_until="domcontentloaded", timeout=args.timeout * 1000)
    if response is None or response.status != 200:
        raise AssertionError(f"HTTP page load failed: {response.status if response else 'no response'}")
    await page.wait_for_selector("#status", state="detached", timeout=args.timeout * 1000)
    await asyncio.wait_for(ready.wait(), timeout=args.timeout)
    await page.wait_for_timeout(1000)
    canvas = page.locator("#canvas")
    canvas_size = await canvas.bounding_box()
    if canvas_size is None or canvas_size["width"] < width * 0.9:
        raise AssertionError(f"Canvas is not filling the viewport: {canvas_size}")
    before = await page.screenshot(path=str(output / f"web-voxel-{name}-initial.png"))
    before_signature, color_spread = image_signature(before)

    if mobile:
        cdp = await context.new_cdp_session(page)
        # Godot's keep-aspect mode fits a 1280x720 game inside a wider phone.
        # Account for those letterbox offsets when injecting native touches.
        scale = min(width / 1280.0, height / 720.0)
        offset_x = (width - 1280.0 * scale) * 0.5
        offset_y = (height - 720.0 * scale) * 0.5
        stick = (1, offset_x + 113.0 * scale, offset_y + (720.0 - 198.0 + 75.0) * scale)
        stick_up = (1, stick[1], stick[2] - 46.0 * scale)
        jump = (2, offset_x + (1280.0 - 88.0) * scale, offset_y + (720.0 - 142.0 + 44.0) * scale)
        look = (2, offset_x + 1280.0 * scale * 0.72, offset_y + 720.0 * scale * 0.4)
        await touch(cdp, "touchStart", [stick])
        await touch(cdp, "touchMove", [stick_up])
        await page.wait_for_timeout(500)
        await touch(cdp, "touchStart", [stick_up, jump])
        await page.wait_for_timeout(250)
        await touch(cdp, "touchEnd", [stick_up])
        await touch(cdp, "touchStart", [stick_up, look])
        await touch(cdp, "touchMove", [stick_up, (2, look[1] - 52, look[2] + 8)])
        await page.wait_for_timeout(400)
        await touch(cdp, "touchEnd", [])
    else:
        await canvas.click(position={"x": width * 0.5, "y": height * 0.4})
        await page.keyboard.down("w")
        await page.wait_for_timeout(1000)
        await page.keyboard.up("w")
    await page.wait_for_timeout(250)
    after = await page.screenshot(path=str(output / f"web-voxel-{name}.png"))
    after_signature, _ = image_signature(after)
    if before_signature == after_signature:
        raise AssertionError(f"{name}: world pixels did not change after movement/look input")

    await page.keyboard.press("m")
    await page.wait_for_timeout(500)
    overview = await page.screenshot(path=str(output / f"web-voxel-{name}-overview.png"))
    overview_signature, _ = image_signature(overview)
    if overview_signature == after_signature:
        raise AssertionError(f"{name}: overview camera did not change the rendered world")
    await page.keyboard.press("m")
    await page.wait_for_timeout(100)
    if fatal:
        raise AssertionError(f"{name}: script/JavaScript errors: {fatal}")
    result = {
        "profile": name, "viewport": [width, height], "touch": mobile,
        "status_overlay_removed": True, "voxel_world_ready": ready.is_set(),
        "world_pixels_changed_after_input": True, "overview_camera_changed": True,
        "rgb_standard_deviation": color_spread, "fatal_errors": fatal,
        "console_errors": console_errors,
        "screenshot": str(output / f"web-voxel-{name}.png"),
    }
    await context.close()
    return result


async def run(args):
    args.output.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(
            executable_path=args.browser,
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu-sandbox",
                  "--use-gl=angle", "--use-angle=swiftshader", "--enable-webgl",
                  "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
        )
        results = []
        for profile in [("desktop", 1280, 720, False), ("mobile", 844, 390, True)]:
            if args.profile != "all" and profile[0] != args.profile:
                continue
            result = await check_profile(browser, args, *profile)
            results.append(result)
            print(json.dumps(result, ensure_ascii=False), flush=True)
        await browser.close()
    (args.output / "web-smoke-results.json").write_text(
        json.dumps({"renderer": "Chromium SwiftShader; not a phone benchmark", "results": results},
                   ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8080/")
    parser.add_argument("--browser", default=shutil.which("chromium") or shutil.which("google-chrome"))
    parser.add_argument("--output", type=Path, default=Path("captures"))
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--profile", choices=["all", "desktop", "mobile"], default="all")
    args = parser.parse_args()
    if not args.browser:
        parser.error("Install Chromium or pass --browser /path/to/browser")
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
