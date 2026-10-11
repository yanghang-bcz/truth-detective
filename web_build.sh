#!/usr/bin/env bash
# Truth Detective • 网页版构建与打包
#
# 作用：一条命令把「Godot 的 Web 导出」和「同域后端」组装成可直接发布的目录。
#
# 用法：
#   ./web_build.sh             导出 + 组装（密钥从 config/local.env 或环境变量取）
#   ./web_build.sh --serve     组装后在本机起服务，浏览器打开 http://127.0.0.1:8080 实测
#
# 产物目录：build/web
#   index.html/js/wasm/pck    Godot 导出产物（静态托管）
#   server.js / package.json  同域后端：静态托管 + /api/analyst 代理
#   case/                     案件原始数据（服务端用来识别「编造的证据编号」）
#   deepseek.key              上游密钥 —— **只存在于服务端**，且已在 .gitignore 里
#
# 密钥优先级：环境变量 DEEPSEEK_API_KEY > config/local.env
# 全程不把密钥打印到终端。

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$PROJECT_DIR/build/web"
PRESET="Web"
SERVE_PORT="${PORT:-8080}"

find_godot() {
  if [[ -n "${GODOT_BIN:-}" && -x "${GODOT_BIN:-}" ]]; then echo "$GODOT_BIN"; return; fi
  local c
  for c in \
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "/tmp/truth-godot-runtime/Godot.app/Contents/MacOS/Godot"; do
    if [[ -x "$c" ]]; then echo "$c"; return; fi
  done
  if command -v godot >/dev/null 2>&1; then command -v godot; return; fi
  echo ""
}

GODOT="$(find_godot)"
if [[ -z "$GODOT" ]]; then
  echo "找不到 Godot 编辑器。把 Godot.app 放进 /Applications 或 ~/Applications，或设 GODOT_BIN。" >&2
  exit 1
fi

echo "Godot  : $GODOT"
echo "Project: $PROJECT_DIR"
echo "Output : $OUT"

# ── 1. Godot Web 导出 ────────────────────────────────────────────
# 用的是 4.3+ 的单线程模板（export_presets.cfg 里 variant/thread_support=false），
# 因此不需要 SharedArrayBuffer，也就没有 COOP/COEP 那一堆头的要求。
echo "== 1/3 导出 Web 构建 =="
mkdir -p "$OUT"
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "$PRESET" "$OUT/index.html" 2>&1 \
  | grep -viE "^(Godot Engine|libpng)" || true
if [[ ! -f "$OUT/index.pck" || ! -f "$OUT/index.wasm" ]]; then
  echo "导出失败：$OUT 下没有 index.pck / index.wasm" >&2
  exit 1
fi

# ── 2. 组装同域后端 ──────────────────────────────────────────────
echo "== 2/3 组装后端（server.js / package.json / 案件数据）=="
cp "$PROJECT_DIR/server/server.js"    "$OUT/server.js"
cp "$PROJECT_DIR/server/package.json" "$OUT/package.json"
mkdir -p "$OUT/case"
cp "$PROJECT_DIR/data/case_001.json"    "$OUT/case/case_001.json"
cp "$PROJECT_DIR/data/case_001.zh.json" "$OUT/case/case_001.zh.json"

# ── 3. 写入服务端密钥 ────────────────────────────────────────────
echo "== 3/3 配置服务端密钥 =="
KEY="${DEEPSEEK_API_KEY:-}"
if [[ -z "$KEY" && -f "$PROJECT_DIR/config/local.env" ]]; then
  KEY="$(sed -n 's/^[[:space:]]*DEEPSEEK_API_KEY[[:space:]]*=[[:space:]]*//p' "$PROJECT_DIR/config/local.env" \
        | tail -1 | tr -d '"' | tr -d "'" | tr -d '\r' | xargs || true)"
fi

if [[ -n "$KEY" ]]; then
  printf 'DEEPSEEK_API_KEY=%s\n' "$KEY" > "$OUT/deepseek.key"
  chmod 600 "$OUT/deepseek.key"
  echo "  已写入 $OUT/deepseek.key（长度 ${#KEY}，内容不外显）"
else
  rm -f "$OUT/deepseek.key"
  echo "  ⚠ 没有找到密钥：/api/analyst 会返回 503，游戏自动退回离线规则引擎。"
fi

echo ""
echo "组装完成。产物清单："
ls -1 "$OUT" | sed 's/^/  /'

# ── 可选：本机起服务实测 ─────────────────────────────────────────
if [[ "${1:-}" == "--serve" ]]; then
  echo ""
  echo "== 本机实测：http://127.0.0.1:$SERVE_PORT =="
  PORT="$SERVE_PORT" node "$OUT/server.js"
fi
