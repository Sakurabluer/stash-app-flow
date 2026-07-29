# Stash Flow 源码备份与恢复手册

## 备份信息

- 应用名称：Stash Flow
- 应用包名：`io.github.sakurabluer.stashflow`
- 应用版本：`1.0.1+2`
- Flutter：`3.44.8`
- Dart：`3.12.2`
- Android 最低版本：API 26（Android 8.0）
- 备份日期：2026-07-29

## 压缩包内容

- `lib/`：Flutter 应用全部业务源码
- `android/`：Android 工程、图标和 Gradle Wrapper
- `assets/`：应用资源
- `test/`：单元测试
- `pubspec.yaml`、`pubspec.lock`：依赖与版本锁定
- `analysis_options.yaml`：静态分析规则
- `.metadata`、`.fvmrc`：Flutter 项目信息
- `README.md`、`FLUTTER_DEVELOPMENT_GUIDE.md`：项目说明
- `SOURCE_BACKUP_GUIDE.md`：本手册

压缩包不包含构建产物、Flutter SDK、Gradle 缓存、IDE 配置和
`android/local.properties`。这些文件体积大或包含当前电脑的绝对路径，恢复时会自动生成。

## 安全说明

源码包不包含 Stash Server 地址、真实 API Key、手机本地收藏或播放状态。
API Key 在 Android 安全存储中按服务器独立保存，服务器列表和收藏保存在应用私有数据中。
换电脑构建不受影响；换手机或卸载应用后需要重新添加服务器。

## 环境要求

1. 安装 Flutter `3.44.8`，并确保 `flutter` 命令可用。
2. 安装 Android Studio、Android SDK 和 JDK 17。
3. Android SDK 需要包含 Platform Tools、Build Tools 和 API 36 平台。
4. 执行 `flutter doctor`，处理 Android toolchain 中的错误。
5. 如需接受 Android 许可，执行 `flutter doctor --android-licenses`。

项目原开发环境使用：

- Android SDK：`E:\sdk`
- Android Studio：`E:\androidstudio`
- 项目内 Flutter SDK：`.tooling\flutter`

这些路径只是原环境记录，新电脑可以使用其他路径。

## 恢复项目

解压源码包，进入包含 `pubspec.yaml` 的目录，然后执行：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

构建成功后的 APK 位于：

```text
build\app\outputs\flutter-apk\app-debug.apk
```

安装到已连接的 Android 设备：

```powershell
adb devices
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

`-r` 表示覆盖安装并保留应用数据。不要为解决普通升级问题清除应用数据，否则本地服务器配置和收藏会丢失。

## 发布新版本

发布或传到手机前，在 `pubspec.yaml` 中递增版本，例如：

```yaml
version: 1.0.2+3
```

加号前是用户看到的版本号，加号后是 Android `versionCode`，每次发布必须增大。
当前工程使用 Android debug 签名，仅适合开发测试。正式分发前需要配置独立 release keystore，且密钥文件不能提交或放入普通源码备份。

## 主要模块

- `lib/core/network/stash_api_client.dart`：Stash GraphQL 请求
- `lib/core/server/server_session.dart`：多服务器、凭据和旧配置迁移
- `lib/shared/providers.dart`：媒体库、推荐、收藏和分页状态
- `lib/features/home/`：首页、最近添加和随机推荐
- `lib/features/library/`：媒体库筛选与 Stash 服务端排序
- `lib/features/tags/`：场景分类、标签、视频和图片浏览
- `lib/features/player/`：视频播放、横竖屏、快进和临时倍速
- `lib/features/settings/`：服务器切换、添加和删除

## 当前功能

- 多 Stash Server 保存、切换、删除及旧配置迁移
- 每台服务器独立安全保存 API Key
- 最近添加、随机焦点推荐和随机推荐列表
- 场景分页、搜索、标签筛选、图片浏览
- 按服务器隔离的本地收藏
- Stash 官方场景排序字段及升降序
- 视频详情、文件路径和可点击标签
- 横竖屏播放器、前后 10 秒、长按右侧临时 2 倍速
- 播放控制栏 3 秒自动隐藏

## 验证与排错

- 依赖异常：删除生成的 `.dart_tool/` 后重新执行 `flutter pub get`。
- Android 路径异常：删除旧的 `android/local.properties`，重新执行 Flutter 构建。
- 手机仍显示旧版本：确认 APK 的 `versionCode` 已增大，并核对安装的包名。
- 覆盖安装签名冲突：旧包和新包签名不同，需要先确认是否可以卸载旧包；卸载会删除应用私有数据。
- Stash 数据未更新：在对应页面下拉刷新，或重新启动应用。

恢复完成后，至少执行一次 `flutter analyze`、`flutter test` 和 debug APK 构建。
