#!/usr/bin/env python3
"""スマホ縦画面でMap/Battleの見た目をスクショに残す。

verify.shの段階6(sp.png)は起動直後のTitleしか写らない。Map(ステージ選択)と
Battle(戦闘)の縦画面レイアウトを人が目視できるよう、実ブラウザで
Title→Map→Battle と遷移させて各画面を撮る。

Godotのcanvasはボタンを内部で描くのでDOMセレクタでは押せない。
MapScreen.gd/Battle.gd と同じ計算でノードのbase座標を出し、
device = base * scale(=min(W/1280, H/720)) に直してcanvasを直接クリックする。
拡大率やbiasを変えたらここの既定も合わせること(クリックがノードから外れるため)。

  verify_sp_screens.py <port> <sp_map_out.png> <sp_battle_out.png> [width] [height]

標準出力に "<JS/Godotエラー数>|<map色数>|<battle色数>|<起動したか(1/0)>" を出す。

環境変数:
  WEB_BOOT_MS   Godotの起動を待つミリ秒 (既定: 15000)
  SP_BIAS       縦画面の縦寄せ(MapScreen/Battleのportrait_vertical_biasと一致させる, 既定0.7)
"""
import os
import sys

from playwright.sync_api import sync_playwright

DESIGN_W, DESIGN_H = 1280.0, 720.0

# MapScreen.gd / MapTree の定数。GDScript側と一致させること。
CELL = (64.0, 62.0)
NODE_RADIUS = 18.0
COLUMN_COUNT = 5
STEP_GOAL = 9
PANEL_RIGHT = 316.0
EDGE_MARGIN = 16.0
TITLE_BOTTOM = 52.0

# canvasが単色(＝描画されていない)でないかを数える。verify_web.pyと同じ。
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


def _fit_scale(cx, cy, tx, ty):
    if cx <= 0.0 or cy <= 0.0:
        return 1.0
    return min(tx / cx, ty / cy)


def _placement(sx, sy, vx, vy, hb, vb):
    return (max(0.0, vx - sx) * hb, max(0.0, vy - sy) * vb)


def _map_node_device(scale, base_w, base_h, bias, step, col):
    """MapScreen.gd の縦画面レイアウトを再現し、ノード中心のdevice座標を返す。"""
    span = ((COLUMN_COUNT - 1) * CELL[0], STEP_GOAL * CELL[1])
    content = (span[0] + 2 * NODE_RADIUS, span[1] + 2 * NODE_RADIUS)
    region_pos = (PANEL_RIGHT + EDGE_MARGIN, TITLE_BOTTOM)
    region_size = (base_w - PANEL_RIGHT - 2 * EDGE_MARGIN, base_h - TITLE_BOTTOM - EDGE_MARGIN)
    k = _fit_scale(content[0], content[1], region_size[0], region_size[1])
    scaled = (content[0] * k, content[1] * k)
    off = _placement(scaled[0], scaled[1], region_size[0], region_size[1], 0.5, bias)
    top_left = (region_pos[0] + off[0], region_pos[1] + off[1])
    cell = (CELL[0] * k, CELL[1] * k)
    node_radius = NODE_RADIUS * k
    half_span = (COLUMN_COUNT - 1) * 0.5 * cell[0]
    origin = (top_left[0] + node_radius + half_span, top_left[1] + node_radius)
    base = (origin[0] + (col - 2) * cell[0], origin[1] + step * cell[1])
    return (base[0] * scale, base[1] * scale)


def main() -> int:
    if len(sys.argv) not in (4, 6):
        sys.exit("usage: verify_sp_screens.py <port> <sp_map.png> <sp_battle.png> [width] [height]")
    port, map_png, battle_png = sys.argv[1], sys.argv[2], sys.argv[3]
    width = int(sys.argv[4]) if len(sys.argv) == 6 else 390
    height = int(sys.argv[5]) if len(sys.argv) == 6 else 844
    bias = float(os.environ.get("SP_BIAS", "0.7"))
    boot_ms = int(os.environ.get("WEB_BOOT_MS", "15000"))

    # expandでは scale=min(W/1280, H/720)、base=device/scale。base(0,0)=device(0,0)。
    scale = min(width / DESIGN_W, height / DESIGN_H)
    base_w, base_h = width / scale, height / scale

    # Title「Game Start」: CenterContainerが拡張ビューポート中央に箱を置く。
    # ボタン中心の縦ズレ(+19)は横画面(379-360)と同じで、縦サイズに依らない。
    title_dev = (640.0 * scale, (base_h / 2.0 + 19.0) * scale)
    # Map 段1中央列(必ず到達可能)。
    node_dev = _map_node_device(scale, base_w, base_h, bias, 1, 2)

    errors: list[str] = []
    console: list[str] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": width, "height": height})
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("console", lambda m: console.append(f"[{m.type}] {m.text}"))

        page.goto(f"http://127.0.0.1:{port}/index.html", wait_until="load")
        page.wait_for_timeout(boot_ms)  # wasm取得とGodotのブート

        # Title -> Map
        page.mouse.click(title_dev[0], title_dev[1])
        page.wait_for_timeout(3000)
        page.screenshot(path=map_png)
        map_colors = page.evaluate(_CANVAS_COLORS_JS)

        # Map -> Battle(発射前。アリーナ・コマ・予告・バーの配置が写る)
        page.mouse.click(node_dev[0], node_dev[1])
        page.wait_for_timeout(3000)
        page.screenshot(path=battle_png)
        battle_colors = page.evaluate(_CANVAS_COLORS_JS)

        browser.close()

    booted = any("Godot Engine v" in m for m in console)
    godot_errors = [m for m in console if "ERROR" in m or "SCRIPT ERROR" in m]
    print(f"{len(errors) + len(godot_errors)}|{map_colors}|{battle_colors}|{int(booted)}")

    for e in (errors + godot_errors)[:8]:
        print(f"  {e}", file=sys.stderr)
    if not booted:
        for m in console[-10:]:
            print(f"  console: {m}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
