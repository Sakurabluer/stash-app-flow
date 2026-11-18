# 更新记录

## v1.2.0 — 2026-11-18

### 目录和图片

- 新增“全部”底部入口，集中浏览目录和标签；首页、媒体库保留顶部搜索，搜索返回来源页面。
- 媒体库继续保留视频网格、筛选和排序，常用排序优先显示。
- 读取 Stash 原生目录，补齐纯图片目录和压缩图库；只展示服务器已入库的媒体。
- 目录新增“全部视频 / 全部图片”，汇总当前目录及所有子目录，支持分页、自然文件名排序和添加时间排序。
- 汇总内容显示来源目录并支持跳转；按媒体 ID 去重，隐藏目录同时影响内容和展示计数。
- 图片支持缩略图、加载失败重试、大图缩放、上一张/下一张及跨页浏览。

### 扫描和界面

- 支持手动扫描媒体库或指定目录，显示任务状态；恢复未结束任务，避免重复提交。
- 扫描完成后刷新视频、图片和目录；任务提示可展开或收起。
- 保留常用与隐藏目录、从视频详情进入同目录的能力。
- 首页随机内容改称“随机发现”，近期进度内容改称“最近未看完”。
- 设置统计明确标为连接时统计，移除尚未接入实际行为的开关，整理重复或含义不清的入口。

### 安装与验证

- 本次提供 `arm64-v8a` APK，要求 Android 8.0 或更高版本。
- 正式版本号 `1.2.0`，Android 构建号 `5008`，高于测试版 `5007`，使用原发布签名。
- 通过静态分析及 46 项自动测试；目录与图片功能已在 Stash v0.31.1 联调，并在模拟器验证覆盖安装、导航、汇总和跨页图片浏览。

### 当前限制

- 目录只浏览 Stash 已收录内容，新文件需要服务器扫描入库；压缩图库按服务器原生归属展示。
- 目录汇总用于浏览，不会自动连续播放所有视频。
- 媒体库“未观看 / 4K / 长片”仍筛选已加载的分页；搜索最多展示前 40 项，收藏详情最多读取前 50 项。
- “最近未看完”来自近期添加的视频，不代表所有历史未看完视频。
- 服务端定时扫描插件为独立项目范围，不包含在本次 Android APK 中。


## 历史版本

## 1.0.4 - 2026-10-26

- Added player stream selection using the server's available direct and
  transcoded endpoints, preserving playback position and speed when switching.
- Fixed the playback progress bar and seeking for server-transcoded streams.

## 1.0.2 - 2026-07-30

- Added focal-point pinch zoom from 1x to 5x during video playback.
- Added single-finger panning while zoomed and a one-tap view reset.
- Preserved tap controls and right-side hold-for-2x playback gestures.

## 1.0.1 - 2026-07-29

- Added multi-server profiles with isolated secure API keys and favorites.
- Added scene categories, tags, image browsing, search, and pagination.
- Added Stash server-side scene sorting with Chinese labels.
- Added random home recommendations and original filename display.
- Added scene file paths and navigable tags to scene details.
- Added an adaptive player with auto-hiding controls, orientation support,
  10-second seeking, and hold-for-2x playback.
- Changed the Android application ID to `io.github.sakurabluer.stashflow`.
- Added official release signing and architecture-specific APKs.