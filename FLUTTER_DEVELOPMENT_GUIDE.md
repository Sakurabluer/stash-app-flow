# Stash Mobile Flutter 开发说明

文档状态：Draft 0.1  
目标项目：基于 `stashapp/stash` 的 Android/iOS 移动客户端  
UI 方向：Emby 类移动媒体应用  
渲染框架：Flutter  

## 1. 项目目标

构建一个面向 Stash Server 的移动客户端。App 不复制 Stash Web 管理后台，而是针对触屏浏览和播放重新组织核心功能：

- 连接一个或多个 Stash Server。
- 浏览场景、图库、人物、工作室和标签。
- 提供首页推荐、继续观看、最近添加和收藏入口。
- 支持服务端搜索、筛选、排序和分页。
- 支持视频播放、断点续播、字幕、倍速、画中画和播放进度同步。
- 提供封面缓存、轻量离线索引和可选媒体下载。
- 适配 Android 手机和平板；iOS 使用同一业务与 UI 代码。

首个版本不把扫描、识别、批量编辑等复杂管理能力作为主流程。服务端管理任务可在后续版本以独立的“服务器工具”模块提供。

## 2. 技术栈清单

所有依赖在建项时锁定确切版本，并通过 Renovate 或 Dependabot 分批升级。本文不写死版本号，避免说明文档快速过期。

| 领域 | 推荐技术 | 用途与选择理由 |
| --- | --- | --- |
| UI | Flutter + Material 3 | Android/iOS 共用渲染层，自建主题 Token，不直接使用默认 Material 外观 |
| 语言 | Dart | 开启 sound null safety、strict inference 和严格 lint |
| SDK 管理 | FVM | 固定团队 Flutter SDK 版本，减少构建环境差异 |
| 状态管理/依赖注入 | `flutter_riverpod`、`riverpod_annotation` | 统一页面状态、Repository 注入、异步加载和自动释放 |
| 路由 | `go_router` | 声明式路由、深链、底部导航状态保持 |
| GraphQL | `graphql_flutter` + `graphql_codegen` | 对接 Stash GraphQL、生成类型化请求与响应模型 |
| HTTP/下载 | `dio` | 媒体请求、文件下载、进度、取消和拦截器 |
| 领域模型 | `freezed` + `json_serializable` | 不可变模型、联合状态、JSON 序列化 |
| 本地数据库 | `drift` | 缓存媒体索引、观看进度、收藏映射、同步队列 |
| 安全存储 | `flutter_secure_storage` | API Key、Basic Auth 凭据和服务器敏感配置 |
| 普通设置 | `shared_preferences` | 主题、默认排序、播放偏好等非敏感设置 |
| 图片 | `cached_network_image` | 封面、截图和人物头像缓存 |
| 分页 | `infinite_scroll_pagination` | 场景库、搜索结果和实体详情列表分页 |
| 播放器 | 自定义 `PlayerController` 接口；首选 `media_kit` | 隔离播放器实现，支持后续替换为原生 ExoPlayer/AVPlayer 方案 |
| 后台下载 | `background_downloader` | 系统级下载任务、通知、暂停与恢复 |
| 后台同步 | `workmanager` | Android 后台刷新、进度重试和缓存维护 |
| 网络状态 | `connectivity_plus` | Wi-Fi 限制、离线状态提示；不能替代真实请求探测 |
| 路径/文件 | `path_provider` | 缓存、下载和临时文件路径 |
| 日志 | `talker_flutter` | 结构化日志、开发诊断页；生产环境脱敏 |
| 崩溃监控 | `sentry_flutter`，可选 | 生产崩溃、性能和版本回归监测 |
| 单元测试 | `flutter_test`、`mocktail` | ViewModel、Repository、Mapper 和同步策略测试 |
| 集成测试 | `integration_test` 或 `patrol` | 连接服务器、浏览、搜索和播放流程测试 |
| 截图测试 | `golden_toolkit` | 关键页面和多尺寸视觉回归测试 |

### 2.1 播放器选择说明

播放器必须通过项目自定义接口接入，不允许页面直接依赖第三方播放器类型：

```dart
abstract interface class PlayerController {
  Stream<PlayerState> get state;
  Future<void> open(MediaSource source, {Duration? startAt});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> setSubtitle(SubtitleTrack? track);
  Future<void> enterPictureInPicture();
  Future<void> dispose();
}
```

第一阶段可用 `media_kit` 快速实现多格式播放。若后续发现 Android 硬件解码、DRM、投屏或画中画能力不足，只替换 `PlayerController` 的实现，不改页面和业务层。

投屏、画中画和后台音频属于平台能力，应放在 `platform/player` 适配层。不要在 UI Widget 中直接调用 MethodChannel。

## 3. 架构原则

采用 feature-first 的分层结构，每个业务功能包含自己的 presentation、application 和 data 代码。不要为每个简单对象机械建立完整 Clean Architecture 层级。

```text
lib/
  app/
    app.dart
    bootstrap.dart
    router.dart
    theme/
  core/
    config/
    database/
    errors/
    logging/
    network/
      auth/
      graphql/
      http/
    server/
    widgets/
  features/
    onboarding/
    home/
    library/
    search/
    scene_detail/
    player/
    performers/
    galleries/
    downloads/
    settings/
  platform/
    player/
    picture_in_picture/
    cast/
  shared/
    models/
    repositories/
test/
integration_test/
assets/
```

### 3.1 数据流

```text
Widget
  -> Riverpod Notifier / AsyncNotifier
  -> Repository interface
  -> Remote GraphQL data source / Local Drift data source
  -> Domain model
  -> AsyncValue<ViewState>
  -> Widget
```

约束：

- Widget 只负责布局、动画和发送用户意图。
- Notifier 负责页面状态和用户操作编排，不拼接 GraphQL 字符串。
- Repository 负责远端/本地数据选择、缓存和错误转换。
- GraphQL DTO 不直接进入 UI，必须映射到稳定的领域模型。
- 数据库主键必须包含 `serverId`，为多服务器支持保留空间。

## 4. 应用导航

使用 `GoRouter` 的 `StatefulShellRoute.indexedStack` 保存底部 Tab 的滚动和筛选状态。

| 路由 | 页面 | 说明 |
| --- | --- | --- |
| `/connect` | 服务器连接 | 地址、认证、HTTPS 检查、连接测试 |
| `/home` | 首页 | 推荐头图、继续观看、最近添加、人物轨道 |
| `/library` | 场景库 | 服务端分页、筛选、排序、网格 |
| `/favorites` | 收藏 | 本地收藏或指定服务器标签映射 |
| `/search` | 搜索 | 场景、人物、标签、工作室分组结果 |
| `/settings` | 设置 | 服务器、播放、下载、缓存、调试 |
| `/scenes/:id` | 场景详情 | 全屏封面、元数据、操作和相关推荐 |
| `/player/:id` | 播放器 | 全屏播放、控制器、字幕和画中画 |
| `/performers/:id` | 人物详情 | 人物资料和关联场景 |
| `/galleries/:id` | 图库详情 | 图片浏览和元数据 |
| `/downloads` | 下载管理 | 任务状态、失败重试和空间使用 |

播放器使用独立全屏路由；迷你播放器放在 Shell Scaffold 的底部导航之上，因此切换 Tab 时不会销毁播放会话。

## 5. 原型到 Flutter Widget 的映射

| 网页原型区域 | Flutter 建议实现 |
| --- | --- |
| 推荐头图 | `CustomScrollView` + `SliverAppBar` + `Stack` |
| 横向内容轨道 | 定高 `ListView.separated(scrollDirection: Axis.horizontal)` |
| 最近添加海报 | `AspectRatio` + `CachedNetworkImage` |
| 媒体库 | `PagedGridView` 或分页 `SliverGrid` |
| 底部导航 | `StatefulShellRoute` + 自定义 `NavigationBar` |
| 全屏详情 | 独立 Route + `Hero` 图片过渡 |
| 搜索 | 防抖输入 + Riverpod `AsyncNotifier` + 分页结果 |
| 迷你播放器 | Shell 上层 `AnimatedSize`/`AnimatedSlide` |
| Toast/错误 | `ScaffoldMessenger`，关键错误使用明确的页面状态 |
| 筛选 | 移动端 `showModalBottomSheet`，平板端侧栏 |

设计 Token 建议集中定义：

- 背景：`#101214`
- 一级表面：`#181B1E`
- 二级表面：`#202428`
- 主文字：`#F5F7F5`
- 次文字：`#9DA4A1`
- 强调色：`#52B54B`
- 危险色：`#ED7564`
- 小圆角：6px；容器圆角不超过 8px
- 动画：普通状态切换 180–240ms；全屏 Route 260–320ms

## 6. Stash Server 接入

### 6.1 连接流程

1. 用户输入服务器根地址，例如 `https://stash.example.com`。
2. 规范化 URL，移除末尾多余 `/`，但保留反向代理路径前缀。
3. 尝试访问 GraphQL Endpoint，通常为 `<baseUrl>/graphql`。
4. 按配置添加 API Key 或 Basic Auth；认证 Header 以实际服务器版本为准。
5. 拉取最小查询，记录服务器版本和可用能力。
6. 将凭据写入安全存储；数据库只保存凭据引用。
7. 为服务器生成稳定 `serverId`，建议使用规范化 URL 的 SHA-256 摘要。

### 6.2 Schema 管理

不同 Stash 版本和插件可能扩展 GraphQL Schema。工程中必须保存一份最低支持版本的 Schema：

```text
lib/core/network/graphql/
  schema.graphql
  fragments/
    scene_fields.graphql
    performer_fields.graphql
  operations/
    home.graphql
    scenes.graphql
    scene_detail.graphql
    search.graphql
    activity.graphql
```

推荐工作流：

1. 从最低支持版本的测试服务器导出 `schema.graphql`。
2. 查询写入 `.graphql` 文件，不在 Dart 中拼接字符串。
3. 运行代码生成。
4. CI 检查生成文件是否与操作定义一致。
5. 针对更新版本运行兼容性测试，但客户端只使用最低版本已存在的字段。

概念上需要以下操作，实际名称和参数以目标服务器 Schema 为准：

- 首页：最近添加场景、继续观看、推荐内容。
- 场景库：`findScenes` 类分页查询。
- 场景详情：单场景查询及 paths、files、performers、tags、studio。
- 搜索：场景、人物、工作室和标签查询。
- 播放活动：保存 resume time 和 play duration。
- 元数据更新：评分、观看状态等允许客户端修改的字段。
- 图库：图库列表、详情及图片路径。

### 6.3 媒体路径

Stash 返回的封面、截图、预览、字幕和流媒体路径可能是相对路径。统一由 `ServerUrlResolver` 转换：

```dart
abstract interface class ServerUrlResolver {
  Uri resolve(String serverId, String path);
  Map<String, String> authHeaders(String serverId);
}
```

任何图片或播放器 Widget 都不应自行拼接服务器地址。认证 Header 也必须由同一个服务生成，确保图片、视频和 GraphQL 使用一致的认证方式。

### 6.4 收藏策略

Stash 的“收藏”字段可能因版本或插件而不同。MVP 采用以下策略：

- 默认：收藏保存在本地 Drift，键为 `serverId + sceneId`。
- 可选：用户选择一个服务器标签作为“收藏标签”，收藏时通过 Mutation 添加/移除该标签。
- 不把评分或 `organized` 字段隐式当作收藏，避免破坏服务器原有数据语义。

## 7. 本地数据设计

建议 Drift 表：

### `servers`

- `id`
- `name`
- `baseUrl`
- `credentialRef`
- `serverVersion`
- `capabilitiesJson`
- `lastConnectedAt`

### `scene_cache`

- `serverId`
- `sceneId`
- `title`
- `studioName`
- `coverUrl`
- `durationSeconds`
- `resumeSeconds`
- `playCount`
- `rating100`
- `createdAt`
- `updatedAt`
- `payloadJson`
- `cachedAt`

### `favorites`

- `serverId`
- `entityType`
- `entityId`
- `createdAt`
- `syncState`

### `playback_outbox`

- `id`
- `serverId`
- `sceneId`
- `resumeSeconds`
- `playDurationSeconds`
- `sequence`
- `createdAt`
- `retryCount`

### `downloads`

- `id`
- `serverId`
- `sceneId`
- `sourceUrl`
- `localPath`
- `status`
- `bytesDownloaded`
- `totalBytes`
- `checksum`

缓存策略采用 stale-while-revalidate：先展示未过期的本地数据，同时从服务端刷新。首次连接或强制刷新才显示阻塞式全屏加载。

## 8. 播放与进度同步

### 8.1 播放源

`MediaSource` 至少包含：

- 原始/转码流 URL
- 请求 Header
- MIME type
- 字幕轨道
- 视频时长
- 初始播放位置
- 画质候选列表

优先使用服务端提供的流媒体路径。不要在客户端假设文件系统路径可以直接访问。

### 8.2 进度上报

- 本地播放器每 10–15 秒生成一次最新进度，但不必每次都发网络请求。
- 页面退到后台、暂停、退出播放和视频结束时立即写入 `playback_outbox`。
- 同一 `serverId + sceneId` 只保留 sequence 最大的待同步记录。
- 网络恢复后按顺序回传，成功后删除 Outbox 记录。
- 不允许旧的远端进度覆盖更新的本地进度。
- 接近片尾时标记已观看并将 resume position 清零；阈值建议可配置，默认 90%。

### 8.3 生命周期

- Android 进入后台时保留播放器会话，按用户设置进入画中画或暂停。
- 来电、音频焦点丢失和蓝牙设备断开时暂停。
- 页面销毁不等于播放器销毁；播放器由应用级 Provider 管理。
- 切换服务器时必须先结束当前播放会话。

## 9. 缓存与离线

缓存分三层：

1. GraphQL 内存缓存：当前会话快速复用。
2. Drift 元数据缓存：离线展示标题、封面地址、观看进度和收藏。
3. 文件缓存：图片、短预览、字幕及用户明确下载的媒体。

规则：

- 图片缓存按磁盘空间限制和 LRU 清理。
- 原视频不进入普通缓存，只能通过“下载”操作保存。
- 下载文件使用 App 私有目录，文件名不包含访问令牌。
- 退出服务器账号时允许用户选择保留或清除下载；凭据必须立即删除。
- 离线期间收藏和进度写入 Outbox，恢复连接后再同步。

## 10. 网络与安全

- API Key 和密码只保存在系统安全存储。
- 日志不得记录 Authorization Header、Cookie、完整媒体 URL Query 或用户密码。
- 默认拒绝无效 TLS 证书。
- 自签名证书应通过用户导入证书或确认证书指纹解决；不要实现全局“忽略全部证书错误”。
- 证书例外必须限制到精确 host、port 和指纹。
- 重定向后重新检查目标地址，避免认证 Header 被发送到不同主机。
- App 截图是否需要禁用由用户隐私设置控制；Android 可使用 `FLAG_SECURE`。
- 数据库中的敏感扩展字段应加密或避免持久化。

## 11. 错误与状态设计

统一错误类型：

- `UnauthorizedFailure`
- `ServerUnavailableFailure`
- `TlsFailure`
- `GraphqlFailure`
- `IncompatibleServerFailure`
- `MediaUnavailableFailure`
- `StorageFailure`
- `OfflineFailure`

UI 规则：

- 首屏加载失败显示可操作的重试页。
- 内容轨道加载失败只影响对应轨道，不阻塞整个首页。
- 分页失败保留已加载内容，并在列表尾部提供重试。
- 认证失效跳转重新验证服务器，不直接删除本地数据。
- 播放错误展示可读原因，并允许切换原始流/转码流。

## 12. 性能要求

- 首页首个可交互内容：中端 Android 设备冷启动目标 2.5 秒内。
- 列表滚动目标：稳定 60fps；120Hz 设备避免不必要的同步重建。
- 横向轨道只构建可见项目，禁止 `SingleChildScrollView + Row` 承载长列表。
- 封面按显示尺寸请求，不下载原图后再缩小。
- 搜索输入防抖 300–400ms，并取消旧请求。
- 场景网格使用服务端分页，默认页大小 30–50。
- Riverpod Provider 按 Scene ID 拆分，收藏变化不应重建整个首页。
- 播放器和图片缓存的内存占用需要在真机通过 DevTools 验证。

## 13. 测试计划

### 单元测试

- URL 规范化和相对媒体路径解析。
- GraphQL DTO 到领域模型映射。
- 收藏策略和服务器标签映射。
- 播放进度 Outbox 合并与重试。
- 缓存过期和 stale-while-revalidate 策略。
- 服务器能力降级判断。

### Widget 测试

- 首页加载、空数据、部分失败和离线状态。
- 场景库筛选、排序和分页状态。
- 搜索防抖、无结果和请求失败。
- 详情收藏状态和播放入口。
- 319px、390px、平板宽度及系统大字体。

### 集成测试

- 首次连接测试服务器。
- API Key 失效后的重新认证。
- 浏览场景并打开详情。
- 播放、暂停、拖动和断点续播。
- 离线修改进度后恢复同步。
- 后台下载暂停和恢复。

CI 中使用固定版本的 Stash 测试容器和脱敏测试媒体，避免依赖开发者个人服务器。

## 14. 环境与构建

建议环境：

```text
config/
  dev.json
  staging.json
  production.json
```

通过 `--dart-define-from-file` 注入非敏感构建参数。服务器地址和凭据属于运行时用户数据，不能写入构建配置。

常用命令示例：

```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
fvm flutter test
fvm flutter test integration_test
fvm flutter build apk --release --dart-define-from-file=config/production.json
```

CI 阶段：

1. 校验格式和静态分析。
2. 运行代码生成一致性检查。
3. 运行单元与 Widget 测试。
4. 运行关键 Golden 测试。
5. 构建 Android APK/AAB。
6. 在发布 Tag 上签名并上传制品。

签名文件、Keystore 密码和监控平台 Token 只保存在 CI Secret 中。

## 15. 开发阶段

### 阶段 0：工程基础

- 初始化 Flutter/FVM 工程。
- 建立 lint、主题、路由、Riverpod 和 CI。
- 建立开发用 Stash Server 与测试账号。
- 导出最低支持版本 GraphQL Schema。

完成标准：Android/iOS 均能启动，能切换开发环境，CI 全绿。

### 阶段 1：连接与只读浏览

- 服务器连接和安全存储。
- 首页、场景库、搜索和场景详情。
- GraphQL 类型生成、分页和图片认证加载。
- Drift 基础缓存。

完成标准：可连接真实 Stash Server 并稳定浏览大型媒体库。

### 阶段 2：播放器

- 播放器适配层。
- 原始流/转码流选择。
- 字幕、倍速、手势、进度与迷你播放器。
- 播放活动 Outbox 和断点续播。

完成标准：前后台切换后播放状态正确，进度最终与服务器一致。

### 阶段 3：收藏与离线

- 本地收藏和可选标签同步。
- 图片缓存管理。
- 后台下载、离线索引和空间管理。

完成标准：断网时可查看已缓存元数据和已下载媒体，恢复后无进度冲突。

### 阶段 4：完整媒体实体

- 人物、工作室、标签和图库详情。
- 平板布局、画中画、投屏适配。
- 性能、可访问性和错误体验优化。

完成标准：核心功能达到 Beta 发布标准。

## 16. MVP 验收标准

- 可以保存并切换 Stash Server 连接。
- API Key 不以明文出现在数据库和日志。
- 首页能够显示继续观看和最近添加。
- 场景库支持服务端分页、排序和至少四种常用筛选。
- 搜索请求有防抖、取消和无结果状态。
- 详情页能够显示封面、工作室、人物、标签、文件和播放入口。
- 播放器支持播放/暂停、拖动、倍速、字幕和断点续播。
- 观看进度在离线和网络失败后能够重试。
- 所有列表在 10,000 个以上场景的测试库中仍使用分页，不出现全库加载。
- 319px 手机、常规手机和 Android 平板无内容溢出。
- 核心流程有单元测试、Widget 测试和至少一条真机集成测试。

## 17. 待确认事项

开始 Flutter 编码前需要确认：

1. 最低支持的 Stash Server 版本。
2. 首发仅 Android，还是 Android/iOS 同期。
3. 收藏采用纯本地还是服务器标签同步。
4. 是否必须支持自签名证书。
5. MVP 是否包含下载、画中画和投屏。
6. 播放源优先使用原文件还是服务器转码流。
7. 是否需要多服务器切换。
8. Android 最低 API Level 和目标商店渠道。

在以上事项未全部确认时，可以先完成阶段 0 和只读 GraphQL Spike；涉及数据写入、下载与播放器原生能力的实现需要在确认后冻结接口。
