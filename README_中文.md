# Truth Detective · 可移动侦探版本

这是基于精细街区 V0 制作的可运行 Godot 4.5 玩家演示工程。固定斜俯视，保留原街区光照、微尘和雾；没有任务、UI 或剧情。

## 在 Windows 打开

1. 将整个 `TruthDetective_Player` 文件夹解压到 `D:\Godot\TruthDetective_Player`。
2. 用 Godot 4.5.1 或兼容的 Godot 4.x 导入该文件夹的 `project.godot`。
3. 等待首次资源导入完成，按 F5 运行。macOS 可用 ⌘B。
4. WASD / 方向键移动，按住 Shift 奔跑。方向相对于屏幕，镜头固定；允许组合键斜向行走，不会斜向加速。

本工程实际制作和验证环境为 macOS + Godot 4.5.1。未直接写入 Windows D: 盘，尚未在 Windows 实机验证。运行使用 Forward+，沿用街区 V2 的显卡要求。

## 玩家资产

- `scenes/detective.tscn`：可重复放入其他场景的 CharacterBody3D 玩家。
- `assets/characters/detective.glb`：真正的 3D 网格、7 骨骼蒙皮、Idle / Walk / Run 三种循环动画。
- `scripts/detective.gd`：屏幕方向移动、加减速、转向、重力、台阶检测、动画混合和跌落复位。
- `blender/detective.blend`：可编辑模型源文件；风衣、翻领、双排扣、腰带和帽子可独立调整。
- `blender/build_detective.py`：修改基础人物及生成骨骼和动画的脚本；在 Blender Python 控制台中设置 `PROJECT_DIR` 为本工程的绝对路径，再执行该文件即可重新生成。运行游戏不需要 Blender。

模型约 2,740 三角面，帽顶总高约 1.60 米。脚底原点 Y=0，采用 Godot Y-up，模型面向 +Z。玩家碰撞胶囊高 1.50 米、半径 0.23 米，底部落在原点；帽檐和手臂不参与碰撞。行走速度 2.0 米/秒，奔跑 3.8 米/秒，最多跨越 0.34 米台阶。

身体来自 Kenney Blocky Characters 2.0 的 character-a（CC0）。本次调整了头身比例、身体边缘与袖子形状，更换材质，增加风衣和帽子，并制作了新的简化骨骼动画。没有使用或提取《小小梦魇》的模型或纹理。

动画采用低模分段刚性蒙皮，适合固定远景展示；没有布料模拟、脚部 IK、跳跃或精细手指动画。Run 为独立步态，动画在原地播放，实际位移由 CharacterBody3D 负责。

## 街区接入

默认主场景是 `scenes/playable_neighborhood.tscn`，其中已经放置玩家并配置实体碰撞。原展示场景 `scenes/neighborhood.tscn` 仍保留。

原街区没有任何碰撞。本版从实体网格建立静态碰撞，排除雾、光束和部分地面装饰，再增加地图边界。地铁台阶仍是实体台阶，不连接新场景或任务。

`tools/build_playable.gd` 可从展示场景重新生成玩家及可玩街区；会覆盖对应生成文件，请先保存手工修改。

## 单独放入已有项目

将角色单独包中的 `assets/characters/`、`scripts/detective.gd` 和 `scenes/detective.tscn` 按原相对路径合入项目，然后把 `detective.tscn` 拖进 3D 场景。把根节点置于地面稍上方，确保地面有启用的 StaticBody3D 碰撞和当前 Camera3D。

玩家默认检测物理第 1 层。默认 InputMap 缺少对应动作时，角色会在启动时补充 WASD、方向键和 Shift 绑定。速度、加速度和台阶高度可在 Inspector 调整。不要只缩放 CharacterBody3D 来改变尺寸，应同时调整模型与胶囊尺寸。

## 验证和预览

`previews/player-tests.txt`：Godot 物理引擎实跑 12 项检查，覆盖落地、三段动画存在、屏幕四方向行走、跑速、路沿、餐馆墙体、边界、返回 Idle、跌落复位。所有项目通过。该检查不是街区每条路线的完整穷举。

`previews/playable_neighborhood.png`、`detective_closeup.png`、`detective_walk.png`、`detective_run.png`：Godot 实际渲染截图。

开发验证可执行：

```
Godot --headless --path . --script res://tools/test_player.gd
```

`scripts/preview_capture.gd` 仅当工程根目录存在 `.capture_player` 文件时启用自动截图，正常游戏不移动镜头。截图模式结束后退出运行，标记自动删除。

## 素材许可

Kenney 原始许可位于 `assets/characters/source/License.txt`，来源与修改记录位于 `ASSET_CREDITS.md`。字体许可随原街区保留。
