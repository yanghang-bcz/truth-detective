#!/usr/bin/env bash
# Truth Detective • Godot 启动器
#
# 作用：把「工程目录」和「Godot 编辑器」绑定在一起。不管编辑器装在哪、工程被移动到哪，
#       这个脚本都能自己找到它们。以后所有 Godot 操作都走它，不要手敲绝对路径。
#
# 用法：
#   ./godot.sh                     打开 Godot 编辑器（-= 编辑器模式；这是日常开发入口）
#   ./godot.sh --run               直接运行游戏，等于编辑器里的 F5
#   ./godot.sh --rebuild           重建场景（build_scene → build_playable，顺序不能反）
#   ./godot.sh --test              跑玩法回归测试 + 场景校验
#   ./godot.sh --bench             跑性能基准（真实帧耗时，不受垂直同步影响）
#   ./godot.sh --headless --script res://tools/xxx.gd    其余参数原样透传给 Godot
#
# 环境变量：
#   GODOT_BIN    手动指定编辑器可执行文件，优先级最高

set -euo pipefail

# 工程目录 = 本脚本所在目录。脚本跟着工程走，路径就永远不会错。
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_godot() {
  if [[ -n "${GODOT_BIN:-}" ]]; then
    if [[ -x "$GODOT_BIN" ]]; then echo "$GODOT_BIN"; return; fi
    echo "GODOT_BIN 指向的文件不可执行: $GODOT_BIN" >&2
    exit 1
  fi
  local candidates=(
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot"
    "/Applications/Godot.app/Contents/MacOS/Godot"
    "/tmp/truth-godot-runtime/Godot.app/Contents/MacOS/Godot"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then echo "$c"; return; fi
  done
  if command -v godot >/dev/null 2>&1; then command -v godot; return; fi
  echo ""
}

GODOT="$(find_godot)"
if [[ -z "$GODOT" ]]; then
  echo "找不到 Godot 编辑器。任选其一：" >&2
  echo "  1) 把 Godot.app 放到 /Applications 或 ~/Applications" >&2
  echo "  2) export GODOT_BIN=/path/to/Godot" >&2
  exit 1
fi

run_script() {
  "$GODOT" --path "$PROJECT_DIR" --headless --script "res://tools/$1"
}

case "${1:-}" in
  --run)
    shift
    echo "Godot  : $GODOT"
    echo "Project: $PROJECT_DIR"
    exec "$GODOT" --path "$PROJECT_DIR" "$@"
    ;;
  --rebuild)
    echo "Godot  : $GODOT"
    echo "Project: $PROJECT_DIR"
    echo "== 1/2 生成街区 + 烘焙碰撞体 =="
    run_script build_scene.gd | grep -E "^(Collision|Merged|Scene saved)" || true
    echo "== 2/2 组装可玩场景 =="
    run_script build_playable.gd | grep -E "^Built" || true
    echo "重建完成。注意顺序不能反：build_playable 依赖 build_scene 产出的 neighborhood_collision.res"
    ;;
  --test)
    echo "== 玩法回归测试 =="
    run_script test_player.gd | grep -E "^(PASS|FAIL)" || true
    echo "== 场景校验 =="
    run_script validate_scene.gd | grep -E "^(PASS|ERROR)" || true
    echo "== 地铁口触发冒烟测试（地铁口 → [E] → 案件 → 关闭 → 回到街上）=="
    # 这一条必须用场景方式跑：--script 模式不注册 autoload，引用 CaseState 会编译失败。
    "$GODOT" --path "$PROJECT_DIR" res://tools/test_case_trigger.tscn \
      | grep -E "^(PASS|FAIL|NOTE|CASE_TRIGGER)" || true
    ;;
  --bench)
    "$GODOT" --path "$PROJECT_DIR" --resolution 1280x800 --script res://tools/bench.gd | grep -E "^BENCH" || true
    ;;
  --help|-h)
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  "")
    # 无参数 = 打开编辑器
    echo "Godot  : $GODOT"
    echo "Project: $PROJECT_DIR"
    exec "$GODOT" -e --path "$PROJECT_DIR"
    ;;
  *)
    exec "$GODOT" --path "$PROJECT_DIR" "$@"
    ;;
esac
