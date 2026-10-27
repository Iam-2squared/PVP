#!/usr/bin/env python3
"""Exercise a Godot Web export in desktop and landscape touch Chromium.

Export the current main scene, start tools/serve_preview.py, then run this file.
Optional development dependencies: playwright, Pillow; an installed Chromium.
This checks rendered interaction, not real-device FPS or palace/town traversal.
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
    r"SCRIPT ERROR|Parse Error|Failed to load script|\bERROR:|RuntimeError|Aborted\(|"
    r"WebGL[^\n]*(?:not supported|unsupported|failed to create)", re.IGNORECASE
)
GAME_WIDTH, GAME_HEIGHT = 1280.0, 720.0


def fitted_game_rect(canvas):
    """Godot keeps the 16:9 game inside a possibly wider landscape canvas."""
    scale = min(canvas["width"] / GAME_WIDTH, canvas["height"] / GAME_HEIGHT)
    return {
        "x": canvas["x"] + (canvas["width"] - GAME_WIDTH * scale) / 2,
        "y": canvas["y"] + (canvas["height"] - GAME_HEIGHT * scale) / 2,
        "width": GAME_WIDTH * scale, "height": GAME_HEIGHT * scale, "scale": scale,
    }


def world_pixels(data, rect):
    from PIL import Image

    image = Image.open(io.BytesIO(data)).convert("RGB")
    pixels = bytearray()
    # Fixed central samples exclude the HUD, joystick, and letterbox bars.
    for row in range(50):
        y = round(rect["y"] + rect["height"] * (0.3 + 0.35 * row / 49))
        for column in range(80):
            x = round(rect["x"] + rect["width"] * (0.3 + 0.4 * column / 79))
            pixels.extend(image.getpixel((x, y)))
    spread = sum(statistics.pstdev(pixels[channel::3]) for channel in range(3))
    if spread < 15:
        raise AssertionError(f"Rendered world appears blank: RGB standard deviation={spread:.2f}")
    return {"pixels": pixels, "signature": hashlib.sha256(pixels).hexdigest(),
            "spread": round(spread, 2)}


def world_difference(before, after):
    differences = [abs(a - b) for a, b in zip(before["pixels"], after["pixels"])]
    changed = sum(sum(differences[i:i + 3]) / 3 > 8 for i in range(0, len(differences), 3))
    return {"mean_rgb_difference": round(statistics.mean(differences), 3),
            "changed_pixel_fraction": round(changed / (len(differences) / 3), 4)}


def require_world_change(before, after, action):
    difference = world_difference(before, after)
    if difference["mean_rgb_difference"] < 1.5 or difference["changed_pixel_fraction"] < 0.025:
        raise AssertionError(f"World did not visibly change after {action}: {difference}")
    return difference


async def touch(cdp, event_type, points):
    await cdp.send("Input.dispatchTouchEvent", {
        "type": event_type,
        "touchPoints": [{"x": x, "y": y, "id": touch_id, "radiusX": 1,
                         "radiusY": 1, "force": 1} for touch_id, x, y in points],
    })


async def check_profile(browser, args, name, width, height, mobile):
    context = await browser.new_context(
        viewport={"width": width, "height": height}, device_scale_factor=1,
        has_touch=mobile, is_mobile=mobile,
    )
    page = await context.new_page()
    ready = asyncio.Event()
    logs, fatal, console_errors = [], [], []
    world_info = {}

    def on_console(message):
        text = message.text
        logs.append({"type": message.type, "text": text})
        if "VOXEL_WORLD_READY" in text:
            ready.set()
            try:
                world_info.update(json.loads(text.split("VOXEL_WORLD_READY", 1)[1].strip()))
            except (ValueError, TypeError):
                pass  # Older engine logs may contain a non-JSON diagnostic.
        if message.type == "error":
            console_errors.append(text)
        if FATAL.search(text):
            fatal.append(text)

    page.on("console", on_console)
    page.on("pageerror", lambda error: fatal.append(str(error)))
    try:
        response = await page.goto(args.url, wait_until="domcontentloaded", timeout=args.timeout * 1000)
        if response is None or response.status != 200:
            raise AssertionError(f"HTTP page load failed: {response.status if response else 'no response'}")
        await page.wait_for_selector("#status", state="detached", timeout=args.timeout * 1000)
        await asyncio.wait_for(ready.wait(), timeout=args.timeout)
        await page.wait_for_timeout(args.settle_ms)
        canvas = page.locator("#canvas")
        canvas_rect = await canvas.bounding_box()
        if canvas_rect is None or canvas_rect["width"] < width * 0.9 or canvas_rect["height"] < height * 0.9:
            raise AssertionError(f"Canvas is not filling the viewport: {canvas_rect}")
        rect = fitted_game_rect(canvas_rect)
        cdp = await context.new_cdp_session(page) if mobile else None

        def point(x, y, touch_id=1):
            return touch_id, rect["x"] + x * rect["scale"], rect["y"] + y * rect["scale"]

        async def tap(x, y):
            await touch(cdp, "touchStart", [point(x, y)])
            await page.wait_for_timeout(90)
            await touch(cdp, "touchEnd", [])

        async def capture(suffix):
            data = await page.screenshot(path=str(args.output / f"web-voxel-{name}-{suffix}.png"))
            return world_pixels(data, rect)

        async def overview():
            if mobile:
                await tap(1209, 66)
            else:
                await page.keyboard.press("m")
            await page.wait_for_timeout(args.settle_ms)

        async def next_destination():
            if mobile:
                await tap(1017, 66)
            else:
                await page.keyboard.press("n")
            await page.wait_for_timeout(args.settle_ms)

        initial = await capture("initial")
        # Keep movement isolated: a camera drag or jumping alone cannot pass it.
        if mobile:
            stick = point(113, 597)
            stick_up = point(113, 551)
            await touch(cdp, "touchStart", [stick])
            await touch(cdp, "touchMove", [stick_up])
            await page.wait_for_timeout(args.move_ms)
            await touch(cdp, "touchEnd", [])
        else:
            # The canvas was already checked visible and correctly sized above.
            # Direct native input avoids Locator.click's extra hit-target/RAF
            # checks starving behind a slow software WebGL renderer.
            await page.mouse.click(canvas_rect["x"] + canvas_rect["width"] * 0.5,
                                   canvas_rect["y"] + canvas_rect["height"] * 0.4)
            await page.keyboard.down("w")
            await page.wait_for_timeout(args.move_ms)
            await page.keyboard.up("w")
        await page.wait_for_timeout(args.settle_ms)
        moved = await capture("moved")
        movement_difference = require_world_change(initial, moved, "forward movement")

        await overview()
        map_view = await capture("overview")
        overview_difference = require_world_change(moved, map_view, "opening overview")
        await overview()
        returned = await capture("returned")
        require_world_change(map_view, returned, "returning to first person")
        return_difference = world_difference(moved, returned)
        # Allow small settling/rendering differences, but reject a stuck overview.
        if return_difference["mean_rgb_difference"] >= world_difference(map_view, returned)["mean_rgb_difference"]:
            raise AssertionError(f"Return view is not closer to the original first-person view: {return_difference}")

        if world_info.get("tour_locations", 2) < 2:
            raise AssertionError("Web export lacks the current preview tour; export the updated main scene first")
        await overview()
        await next_destination()  # Also verifies that a tour leaves overview.
        tour_first = await capture("tour-1")
        require_world_change(map_view, tour_first, "tour from overview")
        await next_destination()  # Initial destination can be the spawn; visit another.
        tour_second = await capture("tour-2")
        tour_difference = require_world_change(tour_first, tour_second, "advancing to the next tour destination")

        if fatal or console_errors:
            raise AssertionError(f"Script/JavaScript/console errors: {fatal + console_errors}")
        return {
            "profile": name, "passed": True, "viewport": [width, height], "touch": mobile,
            "status_overlay_removed": True, "voxel_world_ready": ready.is_set(),
            "world": world_info, "movement_difference": movement_difference,
            "overview_difference": overview_difference, "return_difference": return_difference,
            "tour_difference": tour_difference, "tour_steps": 2,
            "tour_input": "native touch" if mobile else "N key",
            "rgb_standard_deviation": initial["spread"],
            "fatal_errors": fatal, "console_errors": console_errors,
        }
    except Exception:
        try:
            await page.screenshot(path=str(args.output / f"web-voxel-{name}-failure.png"))
        except Exception:
            pass
        raise
    finally:
        (args.output / f"web-voxel-{name}-console.json").write_text(
            json.dumps({"logs": logs, "fatal_errors": fatal, "console_errors": console_errors},
                       ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        await context.close()


async def run(args):
    args.output.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(
            executable_path=args.browser, headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu-sandbox",
                  "--use-gl=angle", "--use-angle=swiftshader", "--enable-webgl",
                  "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
        )
        results = []
        try:
            for profile in [("desktop", 1280, 720, False), ("mobile", 844, 390, True)]:
                if args.profile != "all" and profile[0] != args.profile:
                    continue
                try:
                    result = await check_profile(browser, args, *profile)
                except Exception as error:
                    result = {"profile": profile[0], "passed": False, "error": str(error)}
                results.append(result)
                print(json.dumps(result, ensure_ascii=False), flush=True)
        finally:
            await browser.close()
    (args.output / "web-smoke-results.json").write_text(
        json.dumps({"renderer": "Chromium SwiftShader; not a phone benchmark", "results": results},
                   ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return all(result["passed"] for result in results)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8080/")
    parser.add_argument("--browser", default=shutil.which("chromium") or shutil.which("google-chrome"))
    parser.add_argument("--output", type=Path, default=Path("captures"))
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--settle-ms", type=int, default=1200)
    parser.add_argument("--move-ms", type=int, default=1800)
    parser.add_argument("--profile", choices=["all", "desktop", "mobile"], default="all")
    args = parser.parse_args()
    if not args.browser:
        parser.error("Install Chromium or pass --browser /path/to/browser")
    raise SystemExit(0 if asyncio.run(run(args)) else 1)


if __name__ == "__main__":
    main()
