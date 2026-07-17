#!/usr/bin/env python3
"""書き出したWeb版を実ブラウザで起動し、本当に描画されているか確かめる。

Godotのエラーはブラウザ上ではJS例外やコンソール出力として現れるため、
それを拾う。canvasの実ピクセルも読んで、真っ黒/真っ白のまま「起動した
ように見える」状態を弾く。

  verify_web.py <port> <screenshot_out.png>

標準出力に "<JSエラー数>|<canvasの色数>|<Godotが起動したか(1/0)>" を出す。
"""
import sys

from playwright.sync_api import sync_playwright

# canvasが何色使っているか数える。単色＝描画されていない。
# 4色まで数えたら十分なので早期に打ち切る。
_CANVAS_COLORS_JS = """() => {
    const c = document.querySelector('canvas');
    if (!c) return -1;
    const gl = c.getContext('webgl2') || c.getContext('webgl');
    if (!gl) return -2;
    const px = new Uint8Array(4 * c.width * c.height);
    gl.readPixels(0, 0, c.width, c.height, gl.RGBA, gl.UNSIGNED_BYTE, px);
    const seen = new Set();
    for (let i = 0; i < px.length; i += 4) {
        seen.add(px[i] + ',' + px[i + 1] + ',' + px[i + 2]);
        if (seen.size > 4) break;
    }
    return seen.size;
}"""


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit("usage: verify_web.py <port> <screenshot_out.png>")
    port, out_png = sys.argv[1], sys.argv[2]

    errors: list[str] = []
    console: list[str] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("console", lambda m: console.append(f"[{m.type}] {m.text}"))

        page.goto(f"http://127.0.0.1:{port}/index.html", wait_until="load")
        # wasmの取得とGodotのブートに時間がかかる
        page.wait_for_timeout(15000)

        page.screenshot(path=out_png)
        colors = page.evaluate(_CANVAS_COLORS_JS)
        browser.close()

    booted = any("Godot Engine v" in m for m in console)
    print(f"{len(errors)}|{colors}|{int(booted)}")

    for e in errors[:5]:
        print(f"  JSエラー: {e}", file=sys.stderr)
    if not booted:
        for m in console[-10:]:
            print(f"  console: {m}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
