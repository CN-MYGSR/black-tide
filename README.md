# 黑潮行动 / Operation Black Tide

开放世界 PvPvE 军事撤离射击原型 · **Godot 4.7.2**

从「铁砧前线基地」出发，夺取敌方据点，呼叫直升机撤离。路上会遇到敌方班组和第三方小队。

---

## 玩法

```
基地落地 → 领取目标（夺取某据点）→ 横穿岛屿
   → 遭遇敌方小队（共享情报 / 交替掩护）
   → 进入据点圆圈清掉守军，控制进度 0→100%
   → 按 G 呼叫直升机 → 登机结算
```

- 击杀 **+30** 信用点（撤离时结算），完成任务撤离 **+1200 + 战利品**
- 阵亡损失 25% 信用点
- 主菜单里用信用点购买武器 / 配件 / 护甲 / 夜视仪 / 载具

## 操作

| 键 | 功能 | 键 | 功能 |
|---|---|---|---|
| WASD | 移动 | 左键 | 射击 |
| Shift | 冲刺 | 右键 | 瞄准 |
| Ctrl / C | 蹲下 | R | 换弹 |
| 空格 | 跳跃 / 倒地延缓失血 | 1 / 2 | 主武器 / 副武器 |
| F | 交互（搜刮 / 救援 / 上车 / 登机） | 4 / 5 / 6 | 绷带 / 敷料 / 维生素 |
| G | 呼叫撤离 | V | 第一/第三人称 |
| N | 夜视仪 | Esc | 释放鼠标 |

## 内容

- **24 把枪**，现实型号（M4A1 / M16A4 三连发 / HK416 / AK-74M / SVD / PKM …），
  口径、射速、弹匣、射击模式按真枪填；友军发美械、敌人发俄械
- **5 个配件槽**：瞄具 / 枪口 / 握把 / 弹匣 / 枪托
- **护甲 / 头盔 / 夜视仪**：PASGT、IBA、Crye CPC、6B45、FAST MT、AN/PVS-14、AN/PVS-31
- **载具**：SUV / 武装皮卡 / 轻型装甲车 / APC / UH-60 / AH-64（可驾驶，含直升机）
- **AI 小队**：情报共享、两个火力组交替掩护、士气崩溃溃退
- **程序化世界**：1600m 岛屿、8 个手工布局据点、植被 MultiMesh

## 工程结构

```
src/
  autoload/   event_bus / game_state / asset_lib / loadout
  data/       item_db.gd（全部装备数据）
  world/      terrain / poi_builder / world_root / outpost / vehicle / extraction_heli
  player/     player.gd / weapon_defs.gd
  ai/         soldier.gd / squad.gd / character_rig.gd
  ui/         menu.gd / hud.gd
tools/        selftest / integration_test / 各类探针
docs/         设计与技术方案.md
assets/       转换后的 glTF 模型 + 共享图集 + 数据表
_tools/       Unity → Godot 转换流水线（Python + Blender）
```

## 构建

```bash
# 直接运行
godot --path .

# 自检（81 项）
godot --headless --path . res://tools/selftest.tscn

# 集成测试（24 项）
godot --headless --path . res://tools/integration_test.tscn

# 导出 Windows
godot --headless --path . --export-release "Windows Desktop" "build/BlackTide.exe"
```

## 素材

模型来自 **Synty POLYGON Military**，通过 `_tools/` 里的 Blender 无头流水线
从 Unity `.unitypackage` 转换为 glTF（详见 `docs/设计与技术方案.md`）。

> ⚠️ Synty 素材为商业授权资源，本仓库设为 **private**，请勿公开分发模型文件。
