# 验证记录

2026-11-18，在本项目 Windows 环境验证：

- Skill frontmatter 通过 skill-creator 的 `quick_validate.py`；内部参考链接及三个回归场景 JSON 有效。
- `build-arm64.ps1` 通过 PowerShell 语法检查，并实际完成 analyze、46 项 Flutter 测试、release 构建和 APK 校验。
- 该脚本生成的 APK 与用户已验收的 `1.2.0-test`（5007）包 SHA256 相同：`6504fe901eb7c4fb9a02d8cf9fcdaeb1185a3e9daf94b7197417372be34caff0`。
- 校验器读取真实 APK，确认包名、版本、原发布签名和仅 arm64-v8a；错误版本、包含其他 ABI、含指定环境变量内容的包均被拒绝。拒绝内容匹配时不输出环境变量值。
- 再次指定已存在的输出路径会拒绝运行，保留原 APK。

`evals/evals.json` 记录三个决策场景：本地测试包、验收后提交并保留另一任务、Stash 图片递归筛选。已按本次流程人工核对；未进行独立模型对照评测，不将这些场景当作真实发布授权。
