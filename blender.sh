#!/usr/bin/env bash
# Truth Detective • Blender 启动器
#
# 作用：把「工程目录」和「Blender」绑定在一起，并且保证建模脚本导出到本工程里，
#       而不是别的历史路径。
#
# 用法：
#   ./blender.sh                        打开建模文件 blender/detective.blend
#   ./blender.sh --rebuild-detective     无界面重跑 blender/build_detective.py，
#                                        重新生成并导出 assets/characters/detective.glb
#   ./blender.sh --background --python <脚本>     其余参数原样透传给 Blender
#
# 环境变量：
#   BLENDER_BIN    手动指定 Blender 可执行文件，优先级最高

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_blender() {
  if [[ -n "${BLENDER_BIN:-}" ]]; then
    if [[ -x "$BLENDER_BIN" ]]; then echo "$BLENDER_BIN"; return; fi
    echo "BLENDER_BIN 指向的文件不可执行: $BLENDER_BIN" >&2
    exit 1
  fi
  local candidates=(
    "/Applications/Blender.app/Contents/MacOS/Blender"
    "$HOME/Applications/Blender.app/Contents/MacOS/Blender"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then echo "$c"; return; fi
  done
  if command -v blender >/dev/null 2>&1; then command -v blender; return; fi
  echo ""
}

BLENDER="$(find_blender)"
if [[ -z "$BLENDER" ]]; then
  echo "找不到 Blender。任选其一：" >&2
  echo "  1) 安装 Blender.app 到 /Applications" >&2
  echo "  2) export BLENDER_BIN=/path/to/Blender" >&2
  exit 1
fi

case "${1:-}" in
  --rebuild-detective)
    # 侦探角色是脚本程序化生成的，唯一的真源是 blender/build_detective.py。
    # 手改 detective.blend 不会进游戏 —— 改了脚本才需要跑这个命令重新导出 GLB。
    # PROJECT_DIR 同时用环境变量和脚本自身位置传给 Python，双保险。
    echo "Blender: $BLENDER"
    echo "Project: $PROJECT_DIR"
    echo "== 程序化生成侦探模型并导出 GLB =="
    PROJECT_DIR="$PROJECT_DIR" "$BLENDER" --background --python "$PROJECT_DIR/blender/build_detective.py" 2>&1 \
      | grep -E "^(PROJECT_DIR|DETECTIVE_EXPORTED|Error|Traceback|  File)" || true
    echo "导出完成：assets/characters/detective.glb"
    ;;
  --help|-h)
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  "")
    echo "Blender: $BLENDER"
    echo "Project: $PROJECT_DIR"
    exec "$BLENDER" "$PROJECT_DIR/blender/detective.blend"
    ;;
  *)
    exec "$BLENDER" "$@"
    ;;
esac
