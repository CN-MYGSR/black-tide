# 黑潮环境资源升级 · 2026-10-21

已接入游戏的世界生成器，直接用 Godot 打开 `project.godot` 运行即可。

- 使用 Poly Haven 的 8 份 CC0 源资源，转换出 12 个独立环境网格：2 种海岛阔叶树、2 种灌木、3 种草丛、蕨类和 4 种岩石。替换地图中 18 个原环境模型编号；树木通过尺寸组合形成 6 种配置。原模型文件保留。
- 树木近景每棵约 15 万三角面，远景使用完整原树渲染的双交叉透明替身；其余植物与岩石也有独立远景版本。散布按 64 米分块裁剪。草地修正后，默认地图有 94500 簇草和另外 1400 簇蕨类。
- 9 套 ambientCG PBR 材质、共 27 张颜色/法线/粗糙度贴图。地表按海拔、坡度、斑块和据点磨损混合草地、土壤、岩石与沙地；建筑、道路、帐篷、沙袋、木箱及静态道具叠加对应表面细节，保留原图集上的门窗、迷彩与标识。
- 海面增加动态细波和视角反光；补充 FXAA，略提高环境补光。
- 角色、枪械、动画和玩法由其他工作处理；本次没有重建建筑或车辆几何，也没有修改玩家存档。

## 来源和授权

新引入的资源均为 CC0，可修改并随游戏分发：

- [Poly Haven 许可](https://polyhaven.com/license)，原始资源下载地址及 SHA-256 见 `model_sources.json`。
- [ambientCG 许可](https://docs.ambientcg.com/license/)，每份素材页面、下载包与贴图 SHA-256 见 `sources.json`。
- `model_build.json` 记录输出路径、尺寸、面数及远景技术；不改变工程原有素材的授权。

## 复现

在项目根目录执行；Blender 5.2.2 已用于验证：

```powershell
python _tools/fetch_environment_textures.py
python _tools/fetch_environment_models.py
& 'C:/Users/zugsj666/Downloads/blender-5.2.2/blender.exe' --background --factory-startup --python _tools/build_environment_models.py
& 'C:/Users/zugsj666/Downloads/blender-5.2.2/blender.exe' --background --factory-startup --python _tools/build_tree_impostors.py
```

原始下载缓存保存在 `_source/`，不会参与 Godot 导入或导出。仅开发流程依赖 Python 和 Blender，运行游戏无需联网。

环境验证场景为 `tools/environment_preview.tscn`。先以 Godot 编辑器完成导入，再设置 `BLACK_TIDE_ENV_SHOTS` 为截图输出目录运行该场景。它检查模型、尺寸、近远景面数、地形碰撞，并保存基地、草地、村庄、海岸、机场和俯瞰六个固定视角。

环境预览帧率包含地形、建筑、植被、阴影与后处理，不包含角色和战斗 AI，不能当作整局游戏帧率。

本轮验证：六个固定视角的环境检查通过，源文件 79 项 SHA-256 校验通过，24 个输出模型的面数和外部依赖核验通过；工程自检 81 通过 / 0 失败，集成测试 24 通过 / 0 失败。验证使用项目外的独立 APPDATA 测试目录，不写入正常玩家档案。截图位于 `_shots/environment-before/` 和 `_shots/environment-after/`。

`original-code-20261021.zip` 是本次动工前地形、世界生成和据点生成代码的快照，含当时已有的修改。它只用于人工核对与恢复，勿直接覆盖其他聊天后续改动。

## 草地过渡与草甸修正

- 原先的浮点正弦哈希在 GPU 优化后导致相邻噪声单元共享角点取值不一致，形成地图上方块状的草土接缝。改成稳定整数哈希，并放宽混合区间；GPU 渲染回归由 13261 处异常相邻像素跳变降为 0。
- 草地斑块改为更大尺度，降低地面法线强度。新加的草甸横跨约 36–76 米，使用不同长宽比例与随机朝向，边缘逐步稀疏；各据点外围优先安排，其余散布全岛。
- 沿用现有三种草模型，增加细长较高的草叶比例，并按渲染网格三角形计算根部高度。草的远景范围增至 200 米，近远景及消失边缘采用淡出；保留基地和道路附近的活动空间。
- 新截图在 `_shots/grass-smooth-after/`，包括原有六个视角与草甸近景、俯瞰。噪声回归场景为 `tools/terrain_blend_regression.tscn`；同分辨率下修正前后最大单像素跳变由约 0.424 降到约 0.024。
- `grass-transition-before-*.zip` 保存此次修正前的相关代码，供人工核对，不自动覆盖其他工作。
- 修正后的验证：GPU 噪声连续性回归无断点，八个环境视角检查通过，含两项三角形贴地检查的自检 83 通过 / 0 失败，集成测试 24 通过 / 0 失败。测试退出时仍记录有资源引用清理警告，尚未单独追查；没有开展长时间实战或独立 EXE 导出。
