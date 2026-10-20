# 项目长期记忆 — 黑潮行动 / Operation Black Tide

## 工程定位
Godot 4.7.2 开放世界 PvPvE 军事撤离射击原型。工作区 `D:/Escpace Area-12`。
引擎：`D:/Godot/Godot_v4.7.2-stable_win64.exe`
Blender：`D:/Blender/blender.exe`（5.2 LTS）
Python（managed）：`C:/Users/Administrator/.workbuddy-ai/binaries/python/versions/3.13.12/python.exe`

## 素材链路（改动前先读这里）
- 原始包：`E:/BaiduNetdiskDownload/POLYGON Military - Low Poly 3D Art by Synty v1.02.unitypackage`
- `_source/` 解包结果，**有 `.gdignore`**，不要让 Godot 扫描（否则会导入 1600+ FBX，首次导入要 11 分钟）。
- `_build/` 中间产物（manifest / asset_index / model_meta），同样 `.gdignore`。
- 成品：`assets/models/<分类>/*.glb`（756 个）、`assets/textures/`（24 张）、
  `assets/data/model_meta.json`、`assets/data/material_map.json`。

### 转换三条铁律
1. **GLB 不内嵌贴图**。共用图集，内嵌会导致显存里几百份副本。
   材质由 `AssetLib.apply_materials()` 按名字挂共享 `StandardMaterial3D`。
2. **GLB 根节点有 0.01 缩放**（厘米→米）。凡是绕过场景实例、直接拿 mesh 的地方
   （MultiMesh、ImmediateMesh）都必须把这层 transform 乘回去，否则模型大 100 倍。
3. Blender 材质重名会加 `.001` 后缀，`AssetLib._resolve_key()` 负责归一。

## 代码约定
- 系统之间只通过 `EventBus` 信号沟通，不要互相 `get_node`。
- HUD 全部 `_draw` 画，不建 `.tscn`。
- 场景节点在代码里建（`main.tscn` 只有一个根节点 + main.gd）。
- 中文注释；变量名英文。
- 地形顺序固定：`generate → add_pad → apply_pads → build_mesh → build_collision`，不能乱。

## 验证方式（改动后必跑）
```bash
godot --headless --path . res://tools/selftest.tscn         # 38 项
godot --headless --path . res://tools/integration_test.tscn # 17 项
godot --path . res://tools/shot.tscn                        # 9 张截图
```
断言要断言"内容量"（网格数/顶点数/百分比），不要只断言 `!= null`。

## 尚未做
联机、骨骼动画、载具驾驶、枪械改装、数据驱动的据点布局。
