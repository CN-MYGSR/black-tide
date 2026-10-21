# 基础音效

免费资源的原始页面均标明 **CC0**；来源与选用文件如下。下载和核对日期：2026-10-21。

| 文件 | 作者、资源包及来源 | 选用原文件 |
| --- | --- | --- |
| rifle.wav | Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney — [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library) | AR-15/D_24P.wav |
| pistol.wav | 同上 | 1911/A_34P.wav |
| shotgun.wav | 同上 | Mossberg/N_26P.wav |
| reload.wav | SpringySpringo — [Gun reload sounds](https://opengameart.org/content/gun-reload-sounds) | assaultriflereload1_0.wav |
| step.wav | Kenney — [RPG Audio](https://kenney.nl/assets/rpg-audio) | Audio/footstep01.ogg |
| click.wav | Kenney — [Interface Sounds](https://kenney.nl/assets/interface-sounds) | Audio/click_003.ogg |
| success.wav | 同上 | Audio/confirmation_002.ogg |
| failure.wav | 同上 | Audio/error_004.ogg |

已裁去前导静音、截取需要的音段、转成 22050Hz 单声道 PCM 并统一峰值，
原文件与处理后文件的 SHA-256 见 `sources.json`。Kenney 原始许可随本目录保留。
枪声按武器类别复用，不代表每一款武器的精确录音。CC0 说明：
<https://creativecommons.org/publicdomain/zero/1.0/>。

`hurt.wav`、`hit.wav`、`engine.wav`、`helicopter.wav` 由本项目原创合成，
可在本项目中使用、修改和分发，使用 `python _tools/generate_audio.py` 重新生成。
其余八个文件使用 `_tools/prepare_audio.py <下载源目录>` 和 FFmpeg 离线处理；
该目录需要包含解压后的 `firearms/`、`rpg.zip`、`ui.zip` 与下载的 `reload.wav`。

音效在启动时载入，游戏中复用固定数量的播放器。枪声区分手枪、步枪和霰弹枪；
AI 枪声和载具声音有空间衰减，消音器降低玩家枪声。主音量设置统一控制所有声音。
发动机和旋翼为合成循环音效；其余文件为单次播放。游戏运行时不需要 Python、FFmpeg 或网络。
