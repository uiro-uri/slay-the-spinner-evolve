#!/usr/bin/env python3
"""画像が実質ブランク（単色）でないかを色数で判定する。

  check_image.py <image>

標準出力に "<色数> <幅>x<高さ>" を出す。色数が1〜2しかなければ、
ウィンドウは開いたが何も描かれていない状態。
"""
import sys

from PIL import Image


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit("usage: check_image.py <image>")

    img = Image.open(sys.argv[1]).convert("RGB")
    colors = img.getcolors(maxcolors=1 << 24) or []
    print(f"{len(colors)} {img.size[0]}x{img.size[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
