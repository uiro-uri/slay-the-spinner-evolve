#!/usr/bin/env python3
"""実UIの煙感知器。Web書き出しを実ブラウザで数プレイ通し、配線の事故を拾う。

統計はボット(scripts/playtest.sh)が担当。こちらはBattleResolverを経由しない
層(シーン遷移、シグナル配線、入力、Godot→JSの橋)が壊れていないかだけを見る。

  scripts/playtest_ui.py [--plays N] [--port P]

前提: build/web に書き出し済みであること(scripts/verify.shが作る)。
終了コード: 0=エラーなし / 1=JSエラーかGodotエラーを検出。
"""
import argparse
import http.server
import json
import socketserver
import sys
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent.parent
WEB_DIR = REPO / "build" / "web"


def serve(port: int):
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
        *a, directory=str(WEB_DIR), **kw)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def play_once(page, play_no: int) -> list[str]:
    """タイトル→マップ→戦闘(発射)→決着まで1周。拾ったエラーを返す。"""
    problems: list[str] = []

    page.goto(page.url.split("#")[0], wait_until="load")
    page.wait_for_timeout(12000)  # wasmブート

    # タイトル: Game Start (中央ボタン)
    page.mouse.click(640, 379)
    page.wait_for_timeout(2000)

    # マップ: 段1は必ず3ノードで、中央列は常に(640, 142)にある
    page.mouse.click(640, 142)
    page.wait_for_timeout(2000)

    # 戦闘: 左下から中央へ向けてドラッグ発射
    page.mouse.move(500, 520)
    page.mouse.down()
    for i in range(1, 6):
        page.mouse.move(500 - i * 12, 520 + i * 12)
        page.wait_for_timeout(30)
    page.mouse.up()

    # 決着かゲームオーバー(タイトル戻り)まで最大2分+余韻
    page.wait_for_timeout(30000)
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plays", type=int, default=2)
    ap.add_argument("--port", type=int, default=8199)
    args = ap.parse_args()

    if not (WEB_DIR / "index.html").exists():
        print(f"build/web がない。先に scripts/verify.sh を回すこと", file=sys.stderr)
        return 2

    httpd = serve(args.port)
    js_errors: list[str] = []
    godot_errors: list[str] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.on("pageerror", lambda e: js_errors.append(str(e)))
        page.on("console", lambda m: godot_errors.append(m.text)
                if ("ERROR" in m.text or "SCRIPT ERROR" in m.text) else None)

        page.goto(f"http://127.0.0.1:{args.port}/index.html")
        for i in range(args.plays):
            print(f"play {i + 1}/{args.plays} ...")
            play_once(page, i)

        browser.close()
    httpd.shutdown()

    print(f"\nJSエラー: {len(js_errors)} / Godotエラー: {len(godot_errors)}")
    for e in (js_errors + godot_errors)[:10]:
        print(f"  {e}")
    return 1 if (js_errors or godot_errors) else 0


if __name__ == "__main__":
    sys.exit(main())
