# Black Tide 写实角色、枪械与第一人称手臂

2026-10-21，Blender 5.2.2 / Godot 4.7.2。模型使用免费资源重新适配，原作者与许可见 [THIRD_PARTY_ASSETS.md](THIRD_PARTY_ASSETS.md)。

## 交付内容

- `BT_Operator.blend`：1.8 米战术兵，约 7.7 万三角面，PBR 装备/布料/护目镜；重新绑定到游戏的 22 骨骼，保留厘米骨架接口。角色原张开手套由运行时闭合手套替代。
- `BT_FP_M4.blend`、`BT_FP_AK.blend`、`BT_FP_M1911.blend`：可编辑枪械、双臂及手指骨骼，含本项目制作的 `Reload` 动作。
- `assets/models/characters/BT_Operator.glb`、`assets/models/weapons/BT_*.glb`：实际第三人称和军械库模型。
- `BT_FP_SM_Wep_*.blend`、`assets/models/viewmodels/BT_FP_*.glb`：17 款其余枪械逐枪适配的完整第一人称模型与可编辑源文件。24 个装备编号全部使用完整持枪模型，`BT_Arms_*.glb` 仅保留为未来未适配编号的回退。
- `BT_Hand_R/L_Rifle/Pistol.glb`：第三人称闭合手套与测量的手腕坐标，分近远景。展示角色时需通过 `CharacterRig.setup` 和 `attach_weapon` 挂接手套；`tools/remodel_preview.tscn` 已补齐该流程。
- `BT_Operator_Batched.glb`、`BT_Operator_LOD.glb`：原始网格合批与距离减面衍生模型；近 / 中 / 远为 76,589 / 18,380 / 5,360 三角面，共用骨架与图集，12 / 40 米切换。
- `assets/data/third_party_credits.txt`：游戏内可查看的作者、来源、许可与修改说明。

角色的 7 个既有编号共享战术兵网格，以阵营颜色区别。M4/HK 系列共用 M4 外观，AK 系列共用 AK 外观，M1911 单独适配；其余 17 款保留原枪身并校准左右手接触和瞄准坐标。枪械数值、装备编号与存档保持原有定义。

## 第一人称处理

肩位移到镜头后方，调整上臂/前臂形状和袖子体积，保留握把与护木上的手腕位置。袖口使用渐变手部权重，换弹时保持与手套连接；M4 右手拇指和步枪左手无名指、小指重新调整。

手和枪作为同一套持枪模型响应走动、转向摆动和后坐。相机震动与后坐增加相对惯性，避免手臂固定在同一屏幕像素。换弹时用双骨段解算左臂，弹匣在抽出阶段跟随左手；动作时间按现有枪械换弹时长缩放。M4 铁瞄握点单独校准。

第三人称闭合手套随枪上的握点移动，双骨段 IK 让手腕连接袖口；待机、瞄准、转身和行走分别检查连接距离，倒地时手套跟随角色，复起后恢复持枪。每帧重置基础骨骼位置与缩放，防止长时间运行后手臂逐渐缩小。

LOD 生成器在原角色站姿上减面，将越出头盔等边缘的顶点投回原表面，再反算到原蒙皮空间。原 glTF 节点变换、休止矩阵、近景网格和材质保留，避免整套骨架经 Blender 导出改变角色尺寸。近 / 中 / 远实测站姿高度约 1.7999 / 1.7996 / 1.7919 米。

参考 [Valve 铁瞄实现](https://developer.valvesoftware.com/wiki/Adding_Ironsights) 的持枪摆动与瞄准姿势分层，以及 [Epic 第一人称渲染文档](https://dev.epicgames.com/documentation/en-us/unreal-engine/first-person-rendering) 对专用视角模型的说明。本版沿用 Godot 原有相机渲染，没有增加第二个全屏渲染通道。

## 重新生成

在项目根目录运行，源文件手动改过时请先另存。生成器会覆盖上述 Blender、GLB 与对应元数据项。

```powershell
$blender = 'C:\Users\zugsj666\Downloads\blender-5.2.2\blender.exe'
& $blender --background --factory-startup --python _tools/assemble_realistic_assets.py -- operator
& $blender --background --factory-startup --python _tools/assemble_realistic_assets.py -- m4
& $blender --background --factory-startup --python _tools/assemble_realistic_assets.py -- ak
& $blender --background --factory-startup --python _tools/assemble_realistic_assets.py -- pistol
& $blender --background --factory-startup --python _tools/fit_weapon_holds.py -- all
& $blender --background --factory-startup --python _tools/fit_weapon_holds.py -- hands
python _tools/batch_operator.py
& $blender --background --factory-startup --python _tools/build_operator_lods.py
python tools/test_operator_batch.py
python tools/test_operator_lods.py
```

源 GLB 和许可核验 JSON 在 `reference/free_assets/`。`.gdignore` 防止源文件及暂存导出文件被 Godot 重复导入。

## 检查

使用独立 APPDATA，避免触碰正常游戏存档：

```powershell
$env:APPDATA = 'C:\Users\zugsj666\Desktop\qq\validation\remodel-test-profile'
$env:BLACK_TIDE_TEST_PROFILE = '1'
$godot = 'C:\Users\zugsj666\Downloads\godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
& $godot --headless --path . --editor --import
& $godot --path . res://tools/realistic_regression.tscn
& $godot --path . res://tools/codex_repro.tscn
& $godot --path . res://tools/operator_lod_audit.tscn
& $godot --path . res://tools/hold_audit.tscn -- after
```

`realistic_regression` 检查 24 把枪的手臂、完整骨架、相机震动相对位移、走动摆动、肩位、换弹左手位移、瞄点、第三人称挂枪和 PBR 材质，并输出 `_shots/realistic/`。`codex_repro` 覆盖真实关卡、开镜、切枪、载具等，截图在 `_shots/regression/`。截图均为引擎直接渲染。

握持检查已扩展为 134 项，覆盖全部 24 个编号的第一人称双手、第三人称握点、三档持枪姿势、倒地/复起与 1800 帧骨骼缩放稳定性；LOD 另有原始二进制/骨架/蒙皮/身高/姿势边界校验和引擎截图。`hold_audit` 输出 56 张持枪、开镜和第三人称姿势截图。旧版 `realistic_motion` 视频仅为此前版本的动作预览。

本机本轮 128 人动画和渲染夹具：合批模型平均 10.642ms（约 94 FPS），启用距离网格后 9.250ms（约 108 FPS），三角形提交约 2728 万降到 1772 万。夹具不包含完整 AI，不能作为完整关卡 128 人帧率；最终游戏性能以 `tools/performance_probe.tscn` 的固定场景记录为准。

本轮运行时模型切换后重新通过 436 项核心回归、65 项资产预览检查，并完成 60 秒实际交战测试；无脚本错误，静态内存约 215.3 → 212.2 MB、显存约 2016.8 → 1959.5 MB。完整结果在项目旁 `validation/lod-accepted-results.json`，性能原始日志为 `validation/lod-perf-accepted.log`。

原版 14 个模型保存在项目旁 `validation/before-blender-remodel/`；第一轮未采用的粗模与实验资源移入 `validation/remodel-first-pass/`。原版模型文件仍保留在项目中，由 `AssetLib` 按编号映射到新模型。

## 当前范围

角色变体仍共享网格，部分同系列编号共享枪身外观。第三人称已有闭合手指握姿，尚未制作独立的第三人称逐指换弹动画；逐枪空仓换弹、可拆卸配件和布料模拟未包含。大量角色同时近距离显示时仍使用高精度网格，性能取决于目标设备与实际 AI 负载。
