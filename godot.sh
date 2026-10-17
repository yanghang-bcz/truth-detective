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
#   ./godot.sh --test              跑玩法回归 + 场景校验 + 触发冒烟 + AI 层回归
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
    # 每一段单独跑、单独记退出码。
    #
    # 这里**不能**写成 `... | grep ... || true`：管道的退出码是 grep 的，
    # `|| true` 又把它抹平 —— 结果测试全崩，`./godot.sh --test` 照样返回 0。
    # v0.3 之前正是这个写法，这条命令从来没有能力失败，也就没有资格当验收依据。
    TEST_TOTAL=0
    TEST_FAILED=0
    seg() {
      local label="$1"; shift
      local out rc
      echo "$label"
      set +e
      out=$("$@" 2>&1)
      rc=$?
      set -e
      printf '%s\n' "$out" | grep -E '^(PASS|FAIL|NOTE|ERROR|CASE_TRIGGER|AI_TESTS|V03_TESTS)' || true
      TEST_TOTAL=$((TEST_TOTAL + 1))
      if [[ "$rc" -ne 0 ]]; then
        echo "!! ${label} —— 该段退出码 $rc"
        TEST_FAILED=$((TEST_FAILED + 1))
      fi
      return 0
    }

    seg "== 玩法回归测试 ==" \
      "$GODOT" --path "$PROJECT_DIR" --headless --script res://tools/test_player.gd
    # test_player 走的是 automated + test_input 旁路，证明不了"玩家真按键会动"。
    # 网页版最容易死在这一段：物理全绿、角色却站着不动。
    seg "== 真实输入链路（键盘事件 → InputMap → 角色位移）==" \
      "$GODOT" --path "$PROJECT_DIR" --headless --script res://tools/test_input_map.gd
    # test_case_trigger 是把玩家瞬移进触发区的，证明不了"出生点能走到地铁口"。
    # 出生点/碰撞体一改就可能把整局游戏走死，而其它测试全绿。
    seg "== 地铁口可达性（从出生点真的走过去）==" \
      "$GODOT" --path "$PROJECT_DIR" --headless --script res://tools/test_metro_reachability.gd
    seg "== 场景校验 ==" \
      "$GODOT" --path "$PROJECT_DIR" --headless --script res://tools/validate_scene.gd
    # 这一条必须用场景方式跑：--script 模式不注册 autoload，引用 CaseState 会编译失败。
    seg "== 地铁口触发冒烟测试（地铁口 → [E] → 案件 → 关闭 → 回到街上）==" \
      "$GODOT" --path "$PROJECT_DIR" res://tools/test_case_trigger.tscn
    seg "== AI 层回归（Safe Context / Validator / 优雅降级 / 额度与缓存）==" \
      "$GODOT" --path "$PROJECT_DIR" --headless res://tools/test_ai.tscn
    # v0.3 新增。此前 98 项全绿却对 Confidence、状态继承、事件历史、Debrief 内容
    # 零覆盖 —— 代码结构再清晰，也不等于功能是对的。
    seg "== v0.3 验收（Confidence 拖动 / 状态继承 / 切语言 / 事件历史 / Debrief / AI 快照）==" \
      "$GODOT" --path "$PROJECT_DIR" --headless res://tools/test_v03.tscn

    echo
    if [[ "$TEST_FAILED" -ne 0 ]]; then
      echo "== 测试未通过：$TEST_FAILED / $TEST_TOTAL 段失败 =="
      exit 1
    fi
    echo "== 全部 $TEST_TOTAL 段测试通过 =="
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
