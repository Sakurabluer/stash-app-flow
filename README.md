本项目由 AI 辅助开发，欢迎反馈问题或自行编译使用。

# Stash Flow

Stash Flow 是面向 Android 的非官方中文 Stash Server 客户端，支持视频播放、图片浏览、目录汇总、标签收藏和媒体扫描，使用 Flutter 构建。

> 本项目与 Stash 项目及其维护者不存在隶属、授权或背书关系。Stash 名称仅用于说明兼容的服务端。

## 下载与安装

当前版本：[Stash Flow v1.2.0](https://github.com/Sakurabluer/stash-app-flow/releases/tag/v1.2.0)。

- [下载 64 位安卓 APK（arm64-v8a）](https://github.com/Sakurabluer/stash-app-flow/releases/download/v1.2.0/stash-flow-v1.2.0-arm64-v8a.apk)
- [下载 SHA256 校验文件](https://github.com/Sakurabluer/stash-app-flow/releases/download/v1.2.0/stash-flow-v1.2.0-SHA256SUMS.txt)
- 要求 Android 8.0 或更高版本，本版提供 ARM64 安装包。
- 使用原发布签名，支持覆盖升级旧正式版及 1.2.0-test，保留本机连接与收藏。
- 首次使用请连接自己的 Stash Server，并填写 API Key。安装包不附带服务器账号或媒体内容。

## v1.2.0 更新

- 底部导航调整为“首页 / 媒体库 / 收藏 / 全部 / 设置”，搜索保留在首页、媒体库顶部。
- “全部”支持浏览已入库的视频与图片目录、标签、常用目录和隐藏目录。
- 目录新增“全部视频 / 全部图片”，一次浏览当前目录及所有子目录的内容，支持分页、排序和来源目录跳转。
- 补齐纯图片目录与压缩图库浏览，支持缩略图重试、大图缩放、上一张/下一张和跨页查看。
- 支持手动扫描媒体库或指定目录、任务恢复与状态查看，完成后刷新目录和媒体列表。
- 整理重复按钮、调整文案，移除尚未生效的设置开关。

完整更新及现有限制见 [CHANGELOG.md](CHANGELOG.md)。

## 功能

- 保存并切换多个 Stash Server
- 使用 Android 安全存储分别保存 API Key
- 最近添加、随机焦点推荐和随机推荐
- 场景分页、搜索、筛选及 Stash 服务端排序
- 标签浏览，支持视频与图片
- 按服务器隔离的本地收藏
- 视频详情、文件路径和可点击标签
- “全部”页多级目录浏览、图片分页与缩放、子目录视频/图片汇总、常用与隐藏目录、同目录视频
- 手动扫描媒体库或当前目录、查看任务状态及完成后刷新
- 播放器支持切换 Stash 服务端提供的原始流、转码格式和分辨率
- 自动横竖屏播放器、前后 10 秒和临时 2 倍速

## 环境

- Flutter `3.44.8`
- Dart `3.12.2`
- Android API 26 或更高版本
- JDK 17

## 开发

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

详细恢复和构建说明见 [SOURCE_BACKUP_GUIDE.md](SOURCE_BACKUP_GUIDE.md)。
正式发布签名的本机配置说明见 [SIGNING.md](SIGNING.md)。

## 数据与隐私

应用直接连接用户配置的 Stash Server，不提供中转服务，不收集遥测数据。API Key 保存于 Android 安全存储；服务器列表和收藏保存在应用私有数据中。详见 [PRIVACY.md](PRIVACY.md)。

## 内容责任

本项目不附带、托管或分发任何媒体内容。用户应确保有权访问、管理和播放其服务器中的内容，并遵守所在地法律法规。

## 安全

请勿在公开 Issue 中提交 API Key、服务器地址或个人媒体信息。漏洞报告方式见 [SECURITY.md](SECURITY.md)。

## 许可证

项目源码依据 [MIT License](LICENSE) 发布。第三方依赖仍适用各自许可证，参见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
