#!/usr/bin/env bash
# EVOLVE.md 手順0用: Godot 4.7.1 の headless バイナリを用意し、そのパスを標準出力に出す。
#   GODOT_BIN=$(bash scripts/evolve/bootstrap_godot.sh)
# 公式 GitHub releases がプロキシに403で弾かれる実行環境があるため、失敗時は
# mirror.gcr.io (プロキシ許可済み) の barichello/godot-ci:4.7.1 イメージレイヤーから
# /usr/local/bin/godot を抽出するフォールバックを持つ(2026-07-19 のサイクルで実証済みの経路)。
# FORCE_MIRROR=1 でフォールバック経路を直接使う(経路自体のテスト用)。
set -euo pipefail

DEST="${GODOT_DEST:-/tmp/godot-bin}"
BIN="$DEST/godot"
mkdir -p "$DEST"

if [ -x "$BIN" ]; then
  echo "$BIN"
  exit 0
fi

log() { echo "$@" >&2; }

official() {
  curl -fsSL -o "$DEST/godot.zip" \
    https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip
  unzip -oq "$DEST/godot.zip" -d "$DEST"
  mv "$DEST/Godot_v4.7.1-stable_linux.x86_64" "$BIN"
}

mirror() {
  local reg="https://mirror.gcr.io" repo="barichello/godot-ci" token layer
  token=$(curl -fsSL "$reg/v2/token?scope=repository:${repo}:pull" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
  # manifest(indexならamd64を一段辿る)から最大レイヤー = godot入りレイヤーの digest を得る
  layer=$(python3 - "$token" <<'PY'
import json, sys, urllib.request
token = sys.argv[1]
base = "https://mirror.gcr.io/v2/barichello/godot-ci/manifests/"
accept = ", ".join([
    "application/vnd.docker.distribution.manifest.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.index.v1+json",
])
def get(ref):
    req = urllib.request.Request(base + ref, headers={
        "Authorization": "Bearer " + token, "Accept": accept})
    with urllib.request.urlopen(req) as r:
        return json.load(r)
m = get("4.7.1")
if "manifests" in m:
    d = [e["digest"] for e in m["manifests"]
         if e.get("platform", {}).get("architecture") == "amd64"][0]
    m = get(d)
print(max(m["layers"], key=lambda l: l["size"])["digest"])
PY
)
  log "mirror: レイヤー ${layer} をストリーミング抽出中(約1.4GB)"
  curl -fsSL -H "Authorization: Bearer $token" "$reg/v2/${repo}/blobs/${layer}" \
    | tar -xzO --wildcards '*usr/local/bin/godot' > "$BIN"
}

if [ "${FORCE_MIRROR:-0}" = "1" ]; then
  mirror
elif ! official 2>/dev/null; then
  log "公式DLに失敗(プロキシ403等)。mirror.gcr.io フォールバックに切り替え"
  mirror
fi

chmod +x "$BIN"
"$BIN" --version >&2
echo "$BIN"
