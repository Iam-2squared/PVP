#!/usr/bin/env python3
"""Exercise the standalone Godot Web build with mouse/keyboard and native touch.

Dependencies: Python Playwright, Pillow, Chromium. Export Web, serve build/web,
then run: python3 tools/browser_smoke.py --url http://127.0.0.1:8081/
"""
import argparse
import asyncio
import io
import json
import re
import shutil
import statistics
from pathlib import Path

from PIL import Image
from playwright.async_api import async_playwright

JOBS = ["warrior", "mage", "scout", "archer", "cleric", "artisan"]
FATAL = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script|\bERROR:|RuntimeError|Aborted\(", re.I)


def world_sample(data):
    picture = Image.open(io.BytesIO(data)).convert("RGB")
    w, h = picture.size
    values = []
    for y in range(18):
        for x in range(28):
            values.extend(picture.getpixel((round(w * (0.3 + x / 27 * 0.4)), round(h * (0.32 + y / 17 * 0.4)))))
    return values


def difference(first, second):
    return statistics.mean(abs(a - b) for a, b in zip(first, second))


async def check_profile(browser, args, name, width, height, mobile):
    context = await browser.new_context(viewport={"width": width, "height": height}, has_touch=mobile, is_mobile=mobile)
    page = await context.new_page()
    logs, errors = [], []

    def console(message):
        logs.append(message.text)
        if message.type == "error" or FATAL.search(message.text):
            errors.append(message.text)

    page.on("console", console)
    page.on("pageerror", lambda error: errors.append(str(error)))
    cdp = await context.new_cdp_session(page)
    scale = min(width / 1280, height / 720)
    left = (width - 1280 * scale) / 2
    top = (height - 720 * scale) / 2

    def design(x, y, touch_id=1):
        return {"x": left + x * scale, "y": top + y * scale, "id": touch_id}

    def screen(x, y, touch_id=1):
        return {"x": x, "y": y, "id": touch_id}

    async def touch(event, points):
        await cdp.send("Input.dispatchTouchEvent", {"type": event, "touchPoints": [dict(p, radiusX=1, radiusY=1, force=1) for p in points]})

    async def tap(point):
        if mobile:
            await touch("touchStart", [point])
            await page.wait_for_timeout(40)
            await touch("touchEnd", [])
        else:
            await page.mouse.click(point["x"], point["y"])
        await page.wait_for_timeout(250)

    async def capture(suffix):
        return await page.screenshot(path=str(args.output / f"{suffix}-{name}.png"))

    async def start(job, female):
        old = len(logs)
        if mobile:
            await tap(design(1090, 653))
        else:
            await page.keyboard.press("Enter")
        expected = f"PLAYGROUND_PLAY {job} female={'true' if female else 'false'}"
        for _ in range(30):
            if expected in logs[old:]:
                if not mobile:
                    await page.wait_for_function("document.pointerLockElement?.id === 'canvas'")
                await page.wait_for_timeout(250)
                return
            await page.wait_for_timeout(100)
        raise AssertionError(f"Selection did not start requested character: {expected}, recent={logs[-5:]}")

    async def menu():
        if mobile:
            await tap(screen(width - 96 * scale, 46 * scale))
        else:
            await page.keyboard.press("Tab")
            await page.wait_for_function("document.pointerLockElement === null")
        await page.wait_for_timeout(350)

    results = {"profile": name, "viewport": [width, height], "native_touch": mobile}
    try:
        response = await page.goto(args.url, wait_until="domcontentloaded", timeout=120000)
        assert response and response.status == 200, "HTTP build load failed"
        await page.wait_for_selector("#status", state="detached", timeout=120000)
        for _ in range(100):
            if "PLAYGROUND_READY" in logs:
                break
            await page.wait_for_timeout(100)
        assert "PLAYGROUND_READY" in logs, "Game never reached ready state"
        await page.wait_for_timeout(600)
        selection = await capture("selection")
        pixels = world_sample(selection)
        assert statistics.pstdev(pixels) > 8, "No visible 3D character rendering"
        variants = []
        for female in [False, True]:
            await tap(design(233 if female else 100, 656))
            for index, job in enumerate(JOBS):
                await tap(design(170, 252 + index * 55))
                await page.wait_for_timeout(250)
                if female and job == "mage":
                    await capture("selection-mage-female")
                await start(job, female)
                variants.append(f"{job}:{'female' if female else 'male'}")
                print(f"{name}: started {variants[-1]}", flush=True)
                await menu()
        # Use the default warrior and nearby target for real movement/attack UI.
        await tap(design(100, 656))
        await tap(design(170, 252))
        await start("warrior", False)
        await page.wait_for_timeout(500)
        initial = world_sample(await capture("play"))
        if mobile:
            stick = screen(106 * scale, height - 115 * scale, 0)
            up = screen(106 * scale, height - 151 * scale, 0)
            await touch("touchStart", [stick])
            await touch("touchMove", [up])
            await page.wait_for_timeout(650)
            await touch("touchEnd", [])
        else:
            await page.keyboard.down("w")
            await page.wait_for_timeout(650)
            await page.keyboard.up("w")
        await page.wait_for_timeout(200)
        moved = world_sample(await capture("moved"))
        movement = difference(initial, moved)
        assert movement > 1.0, f"Movement produced no visible world change: {movement}"
        # Reset with a full selection/start cycle; then exercise two taps and skill.
        await menu()
        await start("warrior", False)
        await page.wait_for_timeout(300)
        attack = screen(width - 95 * scale, height - 129 * scale, 1)
        if mobile:
            await tap(attack)
            await page.wait_for_timeout(300)
            await tap(attack)
            await tap(attack)
        else:
            await page.mouse.down()
            await page.mouse.up()
            await page.wait_for_timeout(550)
            for _ in range(2):
                await page.mouse.down()
                await page.mouse.up()
                await page.wait_for_timeout(70)
        await page.wait_for_timeout(400)
        await capture("attacked")
        # Multi-touch: keep joystick and camera fingers while another attacks.
        if mobile:
            stick = screen(106 * scale, height - 115 * scale, 0)
            up = screen(106 * scale, height - 148 * scale, 0)
            look = screen(width * 0.65, height * 0.42, 2)
            look_end = screen(width * 0.68, height * 0.42, 2)
            await touch("touchStart", [stick])
            await touch("touchMove", [up])
            await touch("touchStart", [up, look])
            await touch("touchMove", [up, look_end])
            await touch("touchStart", [up, look_end, attack])
            await page.wait_for_timeout(40)
            await touch("touchEnd", [up, look_end])
            await page.wait_for_timeout(70)
            await touch("touchStart", [up, look_end, attack])
            await page.wait_for_timeout(40)
            await touch("touchEnd", [up, look_end])
            await page.wait_for_timeout(300)
            await touch("touchEnd", [])
            await capture("multitouch")
        else:
            await page.keyboard.press("Space")
            await page.wait_for_timeout(120)
            await capture("jump")
            await page.wait_for_timeout(650)
        await menu()
        assert not errors, f"Runtime errors: {errors}"
        results.update(passed=True, variants_started=variants, movement_rgb_difference=round(movement, 3), errors=errors)
        return results
    except Exception:
        await capture("failure")
        raise
    finally:
        (args.output / f"console-{name}.json").write_text(json.dumps({"logs": logs, "errors": errors}, ensure_ascii=False, indent=2) + "\n")
        await context.close()


async def run(args):
    args.output.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(executable_path=args.browser, headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-webgl", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        results = []
        try:
            for profile in [("desktop", 1280, 720, False), ("mobile", 844, 390, True)]:
                results.append(await check_profile(browser, args, *profile))
        finally:
            await browser.close()
            (args.output / "web-results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
        # Keep review artifacts small; action traces and console logs stay ignored.
        docs = Path(__file__).resolve().parents[1] / "docs"
        docs.mkdir(exist_ok=True)
        for filename in ["web-results.json"] + [f"{view}-{profile}.png" for profile in ["desktop", "mobile"] for view in ["selection", "selection-mage-female", "play"]]:
            source = args.output / filename
            destination = docs / filename
            if source.resolve() != destination.resolve():
                shutil.copyfile(source, destination)
        print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8081/")
    parser.add_argument("--browser", default="/usr/bin/chromium")
    parser.add_argument("--output", type=Path, default=Path("captures"))
    asyncio.run(run(parser.parse_args()))
