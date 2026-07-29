注：此为ai编写和发布，起因本人未在git上面看到有stash的中文安卓app，所以用ai编写了这一程序，如有需要请随意编译。如有使用问题可题issues在能力范围内尽量解决

# Stash Flow

Stash Flow 是面向 Android 的非官方 Stash Server 客户端，使用 Flutter 构建。

> 本项目与 Stash 项目及其维护者不存在隶属、授权或背书关系。Stash 名称仅用于说明兼容的服务端。

## 功能

- 保存并切换多个 Stash Server
- 使用 Android 安全存储分别保存 API Key
- 最近添加、随机焦点推荐和随机推荐
- 场景分页、搜索、筛选及 Stash 服务端排序
- 标签和场景分类浏览，支持视频与图片
- 按服务器隔离的本地收藏
- 视频详情、文件路径和可点击标签
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
