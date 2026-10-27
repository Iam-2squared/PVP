#!/usr/bin/env python3
"""Exercise the exported Home → real WebSocket battle → Home flow.

Run the Godot battle server on 8910 and serve the Web export on 8080 first.
Two isolated Chromium contexts are real distinct players. Native pointer/key
and CDP touch input drive the canvas; observed WebSocket replies verify state.
This is functional software-renderer QA, not a smartphone FPS benchmark.
"""
import argparse
import asyncio
import json
import hashlib
import math
from pathlib import Path
import shutil
import time
from collections import Counter

from playwright.async_api import async_playwright
from browser_smoke import FATAL, fitted_game_rect, touch, world_pixels, world_difference


class Flow:
    def __init__(self, args, name, mobile):
        self.args, self.name, self.mobile = args, name, mobile
        self.context = self.page = self.cdp = None
        self.rect = None
        self.logs, self.errors, self.fatal = [], [], []
        self.messages = {}
        self.identity = ""
        self.profile = {}
        self.players = []
        self.sent_types = []
        self.home_pages = 0
        self.enter_count = 0
        self.home_acks = 0
        self.title_ready = False
        self.all_flows = []
        self.frozen = False
        self.moving_inputs = 0

    def console(self, message):
        text = message.text
        self.logs.append({"type": message.type, "text": text})
        if message.type == "error": self.errors.append(text)
        if FATAL.search(text): self.fatal.append(text)
        if "FRONTEND_READY title" in text: self.title_ready = True
        if "FRONTEND_PAGE home" in text:
            self.home_pages += 1
            print(json.dumps({"profile": self.name, "stage": "home_visible", "count": self.home_pages}), flush=True)

    def websocket(self, socket):
        # Never record a full welcome frame: it contains the reconnect token.
        print(json.dumps({"profile": self.name, "stage": "websocket_created"}), flush=True)
        socket.on("framereceived", self.received)
        socket.on("framesent", self.sent)

    def sent(self, payload):
        try: packet = json.loads(payload)
        except (ValueError, TypeError): return
        self.sent_types.append(str(packet.get("type", "")))
        if packet.get("type") == "input" and isinstance(packet.get("move"), list):
            if sum(abs(float(v)) for v in packet["move"]) > 0.05: self.moving_inputs += 1

    def received(self, payload):
        try: packet = json.loads(payload)
        except (ValueError, TypeError): return
        kind = packet.get("type", "")
        self.messages[kind] = self.messages.get(kind, 0) + 1
        if kind == "welcome": self.identity = str(packet.get("player_id", ""))
        if isinstance(packet.get("profile"), dict): self.profile = packet["profile"]
        if kind == "snapshot": self.players = packet.get("players", [])
        if kind == "entered": self.enter_count += 1
        if kind == "profile" and packet.get("in_home") is True: self.home_acks += 1
        if kind == "error": self.fatal.append("Server rejected UI flow: " + str(packet.get("message", "")))
        if kind in ["welcome", "entered"]:
            print(json.dumps({"profile": self.name, "stage": "server_" + kind}), flush=True)

    async def wait(self, predicate, message, timeout=None):
        deadline = time.monotonic() + (timeout or self.args.timeout)
        while time.monotonic() < deadline:
            if predicate(): return
            await asyncio.sleep(0.2)
        raise AssertionError(message)

    async def open(self, browser):
        width, height = (844, 390) if self.mobile else (1280, 720)
        self.context = await browser.new_context(viewport={"width": width, "height": height},
            device_scale_factor=1, has_touch=self.mobile, is_mobile=self.mobile)
        self.page = await self.context.new_page()
        self.cdp = await self.context.new_cdp_session(self.page)
        await self.cdp.send("Page.enable")
        await self.activate()
        self.page.set_default_timeout(self.args.timeout * 1000)
        self.page.on("console", self.console)
        self.page.on("pageerror", lambda error: self.fatal.append(str(error)))
        self.page.on("websocket", self.websocket)
        response = await self.page.goto(self.args.url, wait_until="domcontentloaded")
        assert response is not None and response.status == 200, "Web export did not load over HTTP"
        await self.page.wait_for_selector("#status", state="detached")
        await self.wait(lambda: self.title_ready, "Godot title did not initialize")
        print(json.dumps({"profile": self.name, "stage": "title_ready"}), flush=True)
        await self.page.wait_for_timeout(self.args.settle_ms)
        canvas = await self.page.locator("#canvas").bounding_box()
        assert canvas, "Godot canvas has no visible bounds"
        self.rect = fitted_game_rect(canvas)
        await self.capture("title")
        await self.tap(640, 500)
        await self.wait(lambda: self.home_pages >= 1, "START did not reach Home")
        await self.page.wait_for_timeout(self.args.settle_ms)
        await self.capture("home")
        if not self.mobile:
            await self.page.screenshot(path=str(self.args.docs / "battle-home.png"))

    def point(self, x, y, finger=1):
        return finger, self.rect["x"] + x * self.rect["scale"], self.rect["y"] + y * self.rect["scale"]

    async def activate(self):
        # One software GPU services both real browser users. Freeze only the
        # inactive page's renderer, as Chrome does for background tabs; sockets
        # remain connected and the game's own snapshot ACK bounds their queue.
        for other in self.all_flows:
            if other is not self and other.page and not other.frozen:
                await other.page.evaluate("document.exitPointerLock && document.exitPointerLock()")
        if self.cdp:
            await self.cdp.send("Page.setWebLifecycleState", {"state": "active"})
        self.frozen = False
        await self.page.bring_to_front()
        for other in self.all_flows:
            if other is not self and other.cdp and not other.frozen:
                await other.cdp.send("Page.setWebLifecycleState", {"state": "frozen"})
                other.frozen = True

    async def tap(self, x, y):
        if self.mobile:
            await touch(self.cdp, "touchStart", [self.point(x, y)])
            await self.page.wait_for_timeout(110)
            await touch(self.cdp, "touchEnd", [])
        else:
            _, px, py = self.point(x, y)
            await self.page.mouse.click(px, py)

    async def capture(self, name, world=False):
        data = await self.page.screenshot(path=str(self.args.output / f"battle-{self.name}-{name}.png"))
        return world_pixels(data, self.rect) if world else None

    def own(self):
        return next((player for player in self.players if str(player.get("id", "")) == self.identity), None)

    async def enter(self, capture=True):
        await self.activate()
        self.players = []
        old = self.enter_count
        await self.tap(1061, 664)
        await self.wait(lambda: self.enter_count > old, "Battle button did not receive server entry acknowledgement")
        await self.wait(lambda: self.own() is not None, "Server did not publish this player's arena body")
        await self.page.wait_for_timeout(self.args.settle_ms)
        own = self.own()
        assert own["alive"] and own["hp"] > 0, "Player entered dead or without playable HP"
        assert max(abs(float(own["position"][0])), abs(float(own["position"][2]))) < 160, "Spawn is outside the city gates"
        if capture: self.initial_world = await self.capture("arena",world=True)

    async def move(self):
        await self.activate()
        await self.wait(lambda: "snapshot_ack" in self.sent_types, "The real client did not acknowledge a rendered snapshot", timeout=60)
        before = [float(v) for v in self.own()["position"]]
        def distance_from_start():
            current = self.own()
            if not current: return 0.0
            position = current["position"]
            return math.hypot(float(position[0]) - before[0], float(position[2]) - before[2])
        if self.mobile:
            # Arena joystick center=(106,605) in the fixed 1280×720 game.
            await touch(self.cdp, "touchStart", [self.point(106, 605)])
            await touch(self.cdp, "touchMove", [self.point(106, 554)])
            try:
                await self.wait(lambda: distance_from_start() >= 1.2, "Held native joystick did not reach server physics", timeout=60)
            finally:
                await touch(self.cdp, "touchEnd", [])
        else:
            await self.page.locator("#canvas").focus()
            await self.page.keyboard.down("w")
            try:
                await self.wait(lambda: distance_from_start() >= 1.2, "Held native W did not reach server physics", timeout=60)
            finally:
                await self.page.keyboard.up("w")
        await self.page.wait_for_timeout(self.args.settle_ms)
        after = [float(v) for v in self.own()["position"]]
        distance = math.hypot(after[0] - before[0], after[2] - before[2])
        assert distance >= 1.0, f"Native movement did not reach server physics: {distance:.3f}m"
        moved = await self.capture("moved",world=True)
        visual = world_difference(self.initial_world, moved)
        assert visual["changed_pixel_fraction"] >= 0.01, f"3D view did not reflect movement: {visual}"
        return {"authoritative_distance_m": round(distance, 3), "render_difference": visual}

    async def home(self, capture=True):
        await self.activate()
        old = self.home_acks
        old_home_pages=self.home_pages
        before = {key: self.profile.get(key) for key in ["player_id", "level", "exp", "unspent_points", "allocations"]}
        if not self.mobile:
            await self.page.keyboard.press("Escape")
            await self.page.wait_for_timeout(150)
        await self.tap(1183.5, 45)
        await self.wait(lambda: self.home_acks > old, "HUD Home button did not receive authoritative Home acknowledgement")
        await self.wait(lambda: self.home_pages > old_home_pages, "Home UI did not become visible after returning")
        await self.page.wait_for_timeout(self.args.settle_ms)
        await self.page.evaluate("async () => { for(let i=0;i<4;i++) await new Promise(r=>requestAnimationFrame(r)); }")
        if capture:
            await self.capture("returned-home")
            if not self.mobile:
                shutil.copyfile(self.args.output/f"battle-{self.name}-returned-home.png", self.args.docs/"battle-home.png")
        assert before == {key: self.profile.get(key) for key in before}, "Returning Home changed authoritative progression"
        return {"home_acknowledged": True, "progression_preserved": True}

    async def persistence_reload(self):
        identity = self.identity
        self.title_ready = False
        self.home_pages = 0
        self.players = []
        await self.page.reload(wait_until="domcontentloaded")
        await self.page.wait_for_selector("#status", state="detached")
        await self.wait(lambda: self.title_ready, "Reload did not restore title")
        await self.page.wait_for_timeout(self.args.settle_ms)
        await self.tap(640, 500)
        await self.wait(lambda: self.home_pages >= 1, "Reloaded START did not open Home")
        await self.page.wait_for_timeout(self.args.settle_ms)
        await self.enter(capture=False)
        assert self.identity == identity, "Browser reload lost its saved server identity/token"
        await self.home(capture=False)
        return True

    def report(self, movement, returned, persisted):
        if self.errors or self.fatal: raise AssertionError(self.errors + self.fatal)
        assert "snapshot_ack" in self.sent_types, "Rendered snapshots never acknowledged server backpressure"
        return {"profile": self.name, "passed": True,
            "viewport": [844, 390] if self.mobile else [1280, 720],
            "input": "native CDP touch" if self.mobile else "native mouse and keyboard",
            "title_to_home": True, "server_join_acknowledged": self.messages.get("welcome", 0) >= 1,
            "arena_entry_acknowledged": self.enter_count >= 1,
            "rendered_snapshots_acknowledged": "snapshot_ack" in self.sent_types,
            "nonzero_native_input_packets": self.moving_inputs,
            "movement": movement, "return_home": returned,
            "home_touch_controls_work_after_battle": True,
            "saved_identity_reused_after_reload": persisted,
            "level": self.profile.get("level"), "exp": self.profile.get("exp"),
            "unspent_points": self.profile.get("unspent_points"),
            "fatal_errors": self.fatal, "console_errors": self.errors}


async def run(args):
    args.output.mkdir(parents=True, exist_ok=True)
    args.docs.mkdir(parents=True, exist_ok=True)
    flows = [Flow(args, "desktop", False), Flow(args, "mobile", True)]
    for flow in flows: flow.all_flows = flows
    result = {"renderer": "Two isolated Chromium SwiftShader processes; not a smartphone benchmark",
        "automation_scheduling": "Inactive renderer frozen with Chrome Page lifecycle; both real WebSockets stay connected and the game sends its own snapshot ACKs.", "results": []}
    async with async_playwright() as p:
        launch_args=[
            "--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu-sandbox", "--use-gl=angle",
            "--use-angle=swiftshader", "--enable-webgl", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
        browsers=[await p.chromium.launch(executable_path=args.browser,headless=True,args=launch_args) for _ in flows]
        try:
            for flow,browser in zip(flows,browsers):
                await flow.open(browser)
                print(json.dumps({"profile": flow.name, "stage": "home_ready"}), flush=True)
            # Initialize both lightweight WebGL engines before loading the city;
            # this prevents one SwiftShader world starving the second boot.
            for flow in flows:
                await flow.enter()
                print(json.dumps({"profile": flow.name, "stage": "entered"}), flush=True)
            assert flows[0].identity and flows[1].identity and flows[0].identity != flows[1].identity, "Isolated contexts did not create distinct players"
            for flow in flows:
                await flow.activate()
                await flow.wait(lambda f=flow: len(f.players) >= 2, "Two browser users are not present in the same battle")
            result["distinct_real_browser_users"] = True
            result["same_arena_two_player_snapshot"] = True
            await flows[0].activate()
            await flows[0].page.wait_for_timeout(args.settle_ms)
            await flows[0].page.screenshot(path=str(args.docs / "battle-arena.png"))
            for flow in flows:
                movement = await flow.move()
                returned = await flow.home()
                # Returning must restore normal Home touch buttons as well as pixels.
                await flow.enter(capture=False)
                await flow.home(capture=False)
                persisted = await flow.persistence_reload()
                report = flow.report(movement, returned, persisted)
                result["results"].append(report)
                print(json.dumps(report, ensure_ascii=False), flush=True)
        except Exception as error:
            result["passed"] = False
            result["error"] = str(error)
            for flow in flows:
                if flow.page:
                    try: await flow.page.screenshot(path=str(args.output / f"battle-{flow.name}-failure.png"))
                    except Exception: pass
            print(json.dumps({"passed": False, "error": str(error)}, ensure_ascii=False), flush=True)
        finally:
            for flow in flows:
                (args.output / f"battle-{flow.name}-console.json").write_text(json.dumps({
                    "logs": flow.logs, "fatal_errors": flow.fatal, "console_errors": flow.errors,
                    "received_message_counts": flow.messages, "sent_message_counts": dict(Counter(flow.sent_types)),
                    "nonzero_native_input_packets": flow.moving_inputs,
                    "own_body": {k:flow.own()[k] for k in ["position","alive","spawn_protected"] if k in flow.own()} if flow.own() else None}, ensure_ascii=False, indent=2) + "\n")
                if flow.context: await flow.context.close()
            for browser in browsers: await browser.close()
    result["passed"] = result.get("passed", True) and len(result["results"]) == 2 and all(r["passed"] for r in result["results"])
    (args.output / "battle-web-results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    if result["passed"]:
        (args.docs / "battle-web-results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return result["passed"]



async def run_serial(args):
    # Import only the two observed networking facts, never the failed later UI
    # result. A newer local HUD build may reuse this proof only explicitly and
    # only when the networking/progression source files predate that proof.
    proof=json.loads(args.concurrent_proof.read_text())
    assert proof.get("distinct_real_browser_users") and proof.get("same_arena_two_player_snapshot"), "Missing live concurrent-browser evidence"
    pck=Path("build/web/index.pck")
    same_export=args.concurrent_proof.stat().st_mtime>=pck.stat().st_mtime
    network_sources=[Path("scripts/battle")/name for name in
        ["arena_server.gd","arena_client.gd","progression.gd","profile_store.gd"]]
    if not same_export:
        assert args.reuse_network_proof, "Concurrent proof predates the current Web export; explicitly permit unchanged-network proof reuse"
        assert all(path.stat().st_mtime<=args.concurrent_proof.stat().st_mtime for path in network_sources), "Networking/progression source changed after concurrent proof"
    network_hashes={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in network_sources}
    args.output.mkdir(parents=True,exist_ok=True)
    args.docs.mkdir(parents=True,exist_ok=True)
    shipped_proof=args.docs/"battle-concurrent-proof.json"
    if args.concurrent_proof.resolve()!=shipped_proof.resolve():
        shutil.copy2(args.concurrent_proof,shipped_proof)
    result={"renderer":"Chromium SwiftShader; not a smartphone benchmark",
        "automation_scheduling":"Concurrent two-browser join was verified separately; native UI control/persistence checks run one browser at a time to avoid shared software-GPU contention.",
        "concurrent_proof_build":"same export" if same_export else "Earlier export with the same networking/progression sources; latest export additionally fixes hidden HUD input interception.",
        "network_source_sha256":network_hashes,
        "ui_test_export_sha256":hashlib.sha256(pck.read_bytes()).hexdigest(),
        "concurrent_join_proof":shipped_proof.name,
        "concurrent_phase_outcome":{"network_join_passed":True,
            "full_ui_phase_passed":proof.get("passed",False),
            "later_ui_failure":proof.get("error")},
        "distinct_real_browser_users":True,"same_arena_two_player_snapshot":True,"results":[]}
    async with async_playwright() as p:
        for name,mobile in [("desktop",False),("mobile",True)]:
            browser=await p.chromium.launch(executable_path=args.browser,headless=True,args=[
                "--no-sandbox","--disable-dev-shm-usage","--disable-gpu-sandbox","--use-gl=angle",
                "--use-angle=swiftshader","--enable-webgl","--enable-unsafe-swiftshader","--ignore-gpu-blocklist"])
            flow=Flow(args,name,mobile)
            try:
                await flow.open(browser)
                await flow.enter()
                print(json.dumps({"profile":name,"stage":"serial_arena_ready"}),flush=True)
                if not mobile:
                    await flow.page.screenshot(path=str(args.docs/"battle-arena.png"))
                movement=await flow.move()
                print(json.dumps({"profile":name,"stage":"native_movement_verified","movement":movement}),flush=True)
                returned=await flow.home()
                print(json.dumps({"profile":name,"stage":"returned_home_verified"}),flush=True)
                await flow.enter(capture=False)
                await flow.home(capture=False)
                print(json.dumps({"profile":name,"stage":"home_reentry_verified"}),flush=True)
                persisted=await flow.persistence_reload()
                report=flow.report(movement,returned,persisted)
                result["results"].append(report)
                print(json.dumps(report,ensure_ascii=False),flush=True)
            except Exception as error:
                result["passed"]=False
                result["error"]=str(error)
                print(json.dumps({"profile":name,"passed":False,"error":str(error)},ensure_ascii=False),flush=True)
                if flow.page:
                    try:
                        await flow.activate()
                        await flow.page.screenshot(path=str(args.output/f"battle-{name}-failure.png"))
                    except Exception: pass
            finally:
                (args.output/f"battle-{name}-console.json").write_text(json.dumps({
                    "logs":flow.logs,"fatal_errors":flow.fatal,"console_errors":flow.errors,
                    "received_message_counts":flow.messages,"sent_message_counts":dict(Counter(flow.sent_types)),
                    "nonzero_native_input_packets":flow.moving_inputs,
                    "own_body":{k:flow.own()[k] for k in ["position","alive","spawn_protected"] if k in flow.own()} if flow.own() else None},ensure_ascii=False,indent=2)+"\n")
                if flow.context: await flow.context.close()
                await browser.close()
            if result.get("passed") is False: break
    result["passed"]=result.get("passed",True) and len(result["results"])==2 and all(r["passed"] for r in result["results"])
    (args.output/"battle-web-results.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
    if result["passed"]: (args.docs/"battle-web-results.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
    return result["passed"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8080/")
    parser.add_argument("--browser", default=shutil.which("chromium") or shutil.which("google-chrome"))
    parser.add_argument("--output", type=Path, default=Path("captures/battle-web"))
    parser.add_argument("--docs", type=Path, default=Path("docs"))
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--settle-ms", type=int, default=2000)
    parser.add_argument("--concurrent-proof",type=Path,help="Reuse an independently verified concurrent-join phase, then validate native UI controls serially")
    parser.add_argument("--reuse-network-proof",action="store_true",help="Allow a prior-export concurrent proof only when networking/progression sources are unchanged; disclose the build distinction in the report")
    args = parser.parse_args()
    raise SystemExit(0 if asyncio.run(run_serial(args) if args.concurrent_proof else run(args)) else 1)


if __name__ == "__main__": main()
