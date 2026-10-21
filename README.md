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
- 军械库可选择装备到主武器或副武器；结算后按回车回到准备菜单
- 倒地队友按 F 救起；友军会靠近并持续救援 3 秒，维生素在倒地时暂停回血
- 据点占领后停止敌方增援，敌军可以反夺；RIVAL 在圈内时会阻止占领

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

驾驶时 W/S 前后、A/D 转向；直升机用空格/C 升降、Shift 加速，F 下车。

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
  autoload/   event_bus / game_state / asset_lib / loadout / audio_sfx
  data/       item_db.gd（全部装备数据）
  world/      terrain / poi_builder / world_root / outpost / vehicle / extraction_heli
  player/     player.gd
  ai/         soldier.gd / squad.gd / character_rig.gd
  ui/         menu.gd / hud.gd
tools/        selftest / integration_test / 各类探针
docs/         设计与技术方案.md
assets/       转换后的 glTF 模型 + 共享图集 + 数据表
_tools/       Unity → Godot 转换流水线（Python + Blender）
```

## 构建

Windows 本机的 Godot 位于下载目录，可在项目目录用 PowerShell 运行：

```powershell
$godot = "$env:USERPROFILE\Downloads\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
& $godot --path .
```

余额、军械库和设置统一保存在 `user://profile.json`，写入时使用临时文件并保留
上一份有效存档 `profile.json.bak`。旧 `armory.json` 会自动读取并迁移，原文件保留。
购买保存失败会撤销交易并显示提示。结算或设置保存失败会保留内存数据、自动重试，待保存期间普通退出会先尝试写盘；失败时取消退出。类型损坏的主存档会回退有效备份。测试必须使用独立 APPDATA，不要使用正常游戏存档。

```bash
# 直接运行
godot --path .

# 自检（83 项）
godot --headless --path . res://tools/selftest.tscn

# 集成测试（24 项）
godot --headless --path . res://tools/integration_test.tscn

# 游戏回归：切枪/弹药、开镜与玻璃、HUD、角色动画、上下车和驾驶
# 先将 APPDATA 指向独立测试目录，避免测试写入自己的游戏存档。
godot --headless --path . res://tools/codex_repro.tscn
# 去掉 --headless 会同时生成 _shots/regression/ 游戏截图。

# 全项目审查问题回归：另设置 BLACK_TIDE_TEST_PROFILE=1，使用新的独立 APPDATA
godot --headless --path . res://tools/audit_regression.tscn
python tools/test_extract_unitypackage.py

# 性能探针：使用图形模式、BLACK_TIDE_TEST_PROFILE=1 和独立 APPDATA
# 固定地图种子、角色位置与视角，输出加载帧间隔、各画质档位、植被对照、同屏角色和 CPU/GPU/内存数据
# BLACK_TIDE_PERF_SECONDS 可设置每组采样秒数（默认 5）；BLACK_TIDE_SOAK_SECONDS=180 可启用持续交战
# BLACK_TIDE_BASELINE_SHADER 可指向优化前的 terrain_surface.gdshader，执行同场景交替对照
godot --path . res://tools/performance_probe.tscn

# 本轮新增回归：图形模式，独立 APPDATA 和 BLACK_TIDE_TEST_PROFILE=1
godot --path . res://tools/twelve_regression.tscn
python tools/test_operator_batch.py

# 导出 Windows
godot --headless --path . --export-release "Windows Desktop" "build/BlackTide.exe"
```

菜单切页复用已创建的控件，装备变化后才刷新相关内容；模型预览在后台加载，
隐藏的预览不持续绘制。购买失败保留当前页面，开始行动先显示加载提示。
副武器和撤离直升机在开局预载，AI 感知检查错开执行，减少首次操作与集中计算的停顿。
地形改用索引共享顶点，保留原有三角形、法线、地表混合与高度图碰撞，减少构建及顶点存储开销。

基础音效包括玩家/AI 枪声、换弹、脚步、命中、受伤、按钮和任务反馈、载具发动机与旋翼，
受设置中的主音量统一控制。八类使用免费的 CC0 资源，来源和许可见
[音效说明](assets/audio/README.md)。运行时预载并复用固定音频播放器，远处不可听的枪声不占用声音通道。
音频输出与地形回归可用图形模式运行 `res://tools/speed_audio_regression.tscn`，
同样需要 `BLACK_TIDE_TEST_PROFILE=1` 和独立 APPDATA；该测试会检查实际混音数据。

## 本轮优化

1. 结算写盘失败自动重试，重新读档不会覆盖待保存奖励，结算仍只发放一次。
2. 读取前校验存档数值范围、设置与军械库类型，损坏主档回退备份。
3. 菜单预览与正式生成使用同一条模型替换路径，避免后台加载旧模型后又同步加载新模型。
4. 同网格、LOD、空间格的植被合批；固定种子批次约 7,890 → 5,498，保留所有实例。
5. 地表粗糙度打包至颜色 alpha，最多 13 → 9 次采样，跳过零权重层并显式计算梯度；地表贴图启用 mipmap。
6. 模型后台预载，植被分布在线程计算，场景分帧创建；只预载本局两把武器的第一人称模型。
7. 鼠标输入即时更新朝向，相机及持枪视觉按渲染帧更新。
8. 音量即时生效，连续拖动在停止 250ms 后合并写盘。
9. 角色使用保留几何、骨骼、蒙皮的材质图集，独立渲染约 19 → 3 次提交。
10. 换弹使用独立声音通道，切枪、倒地、死亡或结束行动会取消声音。
11. 设置提供高品质、均衡、性能三档，调整抗锯齿、阴影、环境遮蔽与 LOD 阈值；默认保持高品质。
12. 性能探针改为固定种子和冻结场景对照，支持可配置时长、p95/p99、CPU/GPU、内存及持续交战。

运行时使用已验证的 `BT_Operator_LOD.glb`：近、中、远景约 76,589 / 18,380 / 5,360 三角面，12 / 40 米切换；共享原骨架、蒙皮与图集材质。近景保留合批模型的原始网格，两张近景姿势对照截图逐像素一致。
原角色重建后先运行 `python _tools/batch_operator.py`，再用 Blender 后台运行 `_tools/build_operator_lods.py`。用 `python tools/test_operator_batch.py` 和 `python tools/test_operator_lods.py` 校验源哈希、几何、蒙皮、身高与动作边界，避免使用陈旧的衍生资产。
地表贴图修改后运行 `python _tools/pack_terrain.py` 更新打包贴图；保留对应的导入设置以生成 mipmap。

## 素材

角色与常用枪械使用免费模型在 **Blender 5.2.2** 中适配：写实战术兵、M4、AK、M1911，
保留 PBR 材质，增加第一人称双手、手指骨骼与换弹动作。手臂有走动、后坐和相机震动惯性。
24 个装备编号均有完整持枪手臂；其余 17 款沿用原枪身并逐枪适配握点。第三人称使用闭合手套、双臂 IK，检查待机、行走、开镜及倒地后复起时的手腕连接。
7 个角色编号共享战术兵网格并区分阵营配色；同系列枪型暂时共享外观，装备数值和存档编号不变。
可编辑源文件、资产清单与重建方法见 [重建说明](art/black_tide_remodel/README.md)。
免费素材作者和 CC BY 4.0 / CC0 来源见 [素材署名](assets/data/third_party_credits.txt)，主菜单也可查看。
其余模型来自 **Synty POLYGON Military**，通过 `_tools/` 的流水线从 Unity
`.unitypackage` 转换为 glTF（详见 `docs/设计与技术方案.md`）。

> ⚠️ **素材版权说明**
> 未重建的模型、贴图及复用的角色骨骼来自 Synty Studios 的 **POLYGON Military** 商业素材包，
> 版权归 Synty Studios 所有，此处仅作学习与演示用途。
> 如需商用请自行购买授权；请勿将素材文件单独再分发或用于其他项目。

## 素材来源与署名

本节汇总原有素材及本轮新增资源。各项素材分别遵循自己的许可，不因收录于本仓库而改变授权。

| 用途 / 素材 | 作者与来源 | 许可 |
|---|---|---|
| 原有建筑、载具、道具、部分枪械与复用骨架 / POLYGON Military | [Synty Studios](https://syntystore.com/products/polygon-military-pack) | 商业素材，沿用原项目授权要求 |
| 战术角色 / Modern Soldier | [Blue Spirit](https://sketchfab.com/3d-models/modern-soldier-358b4fb07f0146cb9b9063342db5897a)，公开预览副本来源 [AiZity](https://aizity.com/assets/free-3d-model-download/modern-soldier-3d-model) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| M4A1 | [Firewarden3D / Firewarden](https://sketchfab.com/3d-models/m4a1-40d8ef818c7549a896371cbb1f64fec6) | CC BY 4.0 |
| 第一人称手臂 / Fps arms | [DJMaesen / bumstrum](https://sketchfab.com/3d-models/fps-arms-9452ce4cddde4110a4fd73e555a8e412) | CC BY 4.0 |
| AK / 手枪手臂骨架适配来源 | Cransh / ccransh：[AK rig](https://sketchfab.com/3d-models/fps-ak-74m-animations-94be8385c402474cacd39bc096c6ca14)、[pistol rig](https://sketchfab.com/3d-models/fps-pistol-animations-0d7a343dcb6f401197a73c91aee93f6d) | CC BY 4.0 |
| M1911 | [e.belous / egorbelous](https://sketchfab.com/3d-models/m1911-pistol-80a0b8a6c4314da4a7b3a7cfe6cec1d4) | CC BY 4.0 |
| AK-47 枪身及衍生纹理 | [taradavies / AK-47](https://opengameart.org/content/ak-47-1)，经 [Operation Steel Tide / AetherRadar](https://github.com/AetherRadar/operation-steel-tide) 适配 | 原始几何 CC0；衍生纹理 MIT |
| 树木、灌木、草丛、蕨类与岩石 | [Poly Haven](https://polyhaven.com/)；8 份原始资源页面及 SHA-256 见 [模型来源清单](art/environment/model_sources.json) | [CC0](https://polyhaven.com/license) |
| 草地、泥土、岩石、混凝土、道路、木材、织物与金属贴图 | [ambientCG](https://ambientcg.com/)；9 套材质页面及 SHA-256 见 [贴图来源清单](art/environment/sources.json) | [CC0](https://docs.ambientcg.com/license/) |
| 步枪、手枪与霰弹枪声 / The Free Firearm Sound Library | Ben Jaszczak、Brian Nelson、Kevin Heras、Matthew Nanney / [OpenGameArt](https://opengameart.org/content/the-free-firearm-sound-library) | CC0 |
| 换弹音效 / Gun reload sounds | [SpringySpringo](https://opengameart.org/content/gun-reload-sounds) | CC0 |
| 脚步、按钮与任务反馈 / RPG Audio、Interface Sounds | Kenney / [RPG Audio](https://kenney.nl/assets/rpg-audio)、[Interface Sounds](https://kenney.nl/assets/interface-sounds) | CC0 |

枪械及手臂适配副本另经 [cktang88/3d-fps](https://github.com/cktang88/3d-fps) 取得，原作者和许可按各素材分别标注。本项目修改包含角色减面、重新绑骨、尺寸与阵营配色、材质合批和 LOD，以及枪械握点、手臂比例、手指姿势和重新导出；换弹动作由本项目重新制作。环境模型经过减面、远景替身及 Godot 材质适配，音效经过裁剪、采样率转换和音量调整。受伤、命中、发动机与旋翼音效由本项目原创合成。

详细修改记录和许可见 [模型素材说明](art/black_tide_remodel/THIRD_PARTY_ASSETS.md)、[环境说明](art/environment/README.md)及 [音效说明](assets/audio/README.md)。[游戏内素材署名](assets/data/third_party_credits.txt)保留模型作者与 MIT 许可全文，Kenney 原始许可也随音效目录保留。
