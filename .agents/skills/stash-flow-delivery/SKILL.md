---
name: stash-flow-delivery
description: Stash Flow 项目开发与交付流程。修改安卓功能、调整目录/图片/扫描交互、联调 Stash GraphQL、打包 64 位测试 APK、验证覆盖升级，或用户验收后要求更新 Git 时使用。按当前授权完成方案、实现、测试、签名打包、本地交付和提交推送；保留其他任务的改动。
---

# Stash Flow 开发与交付

在仓库根目录执行命令。按当前任务进度接续工作，复用已通过的测试和已验收的 APK；不为提交文档重复构建应用。

## 1. 确定范围与当前状态

- 先查看 `git status --short`、当前分支、远程及相关差异，区分本次功能与其他任务的修改。不重置工作区，不使用 `git add .`。
- 阅读 `pubspec.yaml`、`README.md` 和相关需求文档。目录与图片以 `DIRECTORY_MEDIA_PLAN.md` 为准，`FEATURE_PLAN.md` 保留首版历史。
- 用户只要方案时，先检查现有实现再写方案；用户要求“做一版/APK”时直接实现。仅询问无法从源码、文档和会话推断且影响范围的问题。
- 当前导航职责：**首页 / 媒体库 / 收藏 / 全部 / 设置**。“全部”承担目录、图片、标签和扫描入口；首页与媒体库保留搜索。保留原有筛选、排序，不让统计按钮跳到含义不同的页面。
- 不把计划当成已实现能力。说明分页、筛选、统计等已知限制，不顺带扩大需求。

## 2. 实现与服务器联调

- 延续现有 Flutter、Riverpod、GoRouter、主题及组件。二级搜索返回来源页；目录和汇总页保持“全部”选中；详情、播放器、大图返回列表时保留位置。
- 修改模型时保留媒体全部关联文件；目录范围按路径边界判断，媒体按 ID 去重。隐藏目录、计数和汇总使用相同范围，另一个可见副本仍应可见。
- 目录索引、请求、凭据、收藏和图片缓存按服务器隔离。异步请求使用 generation/request token；服务器切换后丢弃旧结果。
- 先核实当前 Stash schema，再写 GraphQL。普通刷新查询已入库内容；扫描发现新文件。联调只使用本次已授权的服务器及操作，优先只读查询；确需实测扫描时选小目录，不默认执行全库扫描。
- 服务器地址、账号、API Key、媒体清单和运行日志只留在被忽略的本地文件或环境中。不要写入源码、Skill、公开需求文档、APK 或提交说明，不打印秘密值。
- 目录/图片/扫描接口细节见 [references/stash-api.md](references/stash-api.md)。该文件记录已验证语义，升级服务端后重新验证。

## 3. 验证

使用 `.tooling/flutter/bin/flutter.bat`，无本地 SDK 时使用 PATH 中的 Flutter。工具链参考 `SOURCE_BACKUP_GUIDE.md`；签名以 `SIGNING.md` 为准。

1. 格式化修改的 Dart 文件，运行 `flutter analyze` 和适当的 `flutter test`。新测试覆盖真实风险：目录边界、深层递归、多文件去重、隐藏副本、跨页排序、任务恢复、切服竞态与窄屏布局。
2. 接口变更在目标服务器检查本层/递归数量、至少两页去重、缩略图和原图鉴权。大图库只按范围查询计数和分页详情；自然排序需要全范围时，仅拉取该范围的 ID/路径。
3. 条件允许时覆盖安装到现有测试设备：验证导航/返回、视频与图片汇总、图片缩放和跨第 30 张翻页，以及扫描状态。界面截图仅用于本地验证，不将私人媒体截图放进仓库。
4. 记录实际通过的检查和未验证项。失败应修复并复测；不要宣称在模拟器 x86 上运行等同于 ARM 真机测试。

## 4. 构建并交付 ARM64 测试包

- 在 `pubspec.yaml` 递增版本。`versionCode` 应大于用户已安装各版本的最高值；旧的 ABI 拆包可能附加偏移，不能只参考 pubspec。读取设备包信息或既有 APK 核对。
- 使用原发布签名，安全读取 `STASH_FLOW_KEYSTORE`、`STASH_FLOW_KEY_ALIAS`、`STASH_FLOW_STORE_PASSWORD`、`STASH_FLOW_KEY_PASSWORD`；不输出值。签名不符时停止交付，不卸载旧包、不清数据来绕过升级问题。
- 使用脚本构建、验证并复制到新文件（默认不覆盖已有产物）：

```powershell
# 示例版本，执行前替换为本轮实际版本及 build number。
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/stash-flow-delivery/scripts/build-arm64.ps1 `
  -VersionName 1.3.0-test -BuildNumber 5008
```

- 示例的 ExecutionPolicy 参数仅作用于该次 PowerShell 进程，不修改系统策略。
- 脚本执行 analyze、test、签名构建，生成 `release/stash-flow-VERSION-BUILD-arm64.apk` 和 SHA256 文件。只打包 `android-arm64`，不使用 `--split-per-abi`，避免 versionCode 偏移。
- **检查 APK 实际内容**：Flutter 的 target-platform 不一定排除依赖附带的其他 ABI。`android/app/build.gradle.kts` 已对齐依赖的 ABI filters。验收要求 ZIP 内只有 `lib/arm64-v8a/`，并包含 `libapp.so`、`libflutter.so`。
- 复验现成 APK 时可只运行下面的校验器；从环境变量指定需排除的本次真实秘密或私有地址，不在命令行直接传秘密。

```powershell
python .agents/skills/stash-flow-delivery/scripts/verify-apk.py `
  release/stash-flow-1.2.0-test-arm64.apk --sdk E:/sdk `
  --version-name 1.2.0-test --version-code 5007
# 可重复添加 --forbid-env ENV_NAME，扫描 APK 所有文件且不打印变量值。
```

- 本地交付用 APK 的绝对路径链接，说明版本、大小、核心改动、检查结果和限制。`release/`、`build/`、`.tooling/`、签名及本地配置保持忽略；交付 APK 不等于发布 GitHub Release。

## 5. 验收后更新 Git

- 执行用户当前指令：“先不上传 Git”时交付本地包；用户后续说“可以了，更新 Git”即授权提交并推送已验收范围，不重复申请确认。
- 未要求公开发布时只更新源码，不自动建 tag、发布 Release 或上传 APK。若用户明确要求发布，完成包、版本说明和验证后执行其授权范围。
- 更新 README/需求状态，保留尚未实现项。检查准备提交文件有无真实凭据、私有地址或私人媒体数据，必要时替换为通用例子；不要改其他任务的本地文件。
- `git fetch origin` 后检查差异。落后时先保护本地改动再处理；发生分歧不 force push。按现有分支协作方式提交，新建分支时使用 `codex/` 前缀。
- 显式暂存本次路径，检查 `git diff --cached --stat` 与 `git diff --cached --check`，核对没有其他任务和生成产物。提交信息说明最终行为。
- 推送到对应远程分支，再核对本地提交与远程 SHA 一致。失败时保留已提交结果，明确报告失败原因；不能把本地 commit 说成已推送。
- 收尾说明提交号、分支、Skill 路径，以及保留的其他任务改动。按实际情况报告检查，不反复运行已经通过且不受后续修改影响的测试。

## 工作流自检案例

见 [evals/evals.json](evals/evals.json)。这些是决策回归场景，评审时只推演，不把例句当成新的构建、上传或服务器操作授权。
