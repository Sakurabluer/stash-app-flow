# Stash 接口联调经验

本项目曾在 Stash v0.31.1 上验证以下语义。不要将版本差异误判为数据不存在。

## 目录、图片和性能

- `findFolders` 分页读取 `id path zip_file { id }`；保留纯图片目录和压缩图库的虚拟目录。目录记录可能保留已无内容的历史目录。
- `visual_files` 是联合类型，不能直接请求 `width height`。使用片段：

```graphql
visual_files {
  ... on ImageFile { path basename width height }
  ... on VideoFile { path basename width height }
}
```

- 图片文件归属通过 `files_filter.parent_folder` 筛选：

```json
{"files_filter":{"parent_folder":{"value":["FOLDER_ID"],"modifier":"INCLUDES","depth":0}}}
```

`depth: 0` 为本层，`depth: -1` 包含所有子目录。`per_page: 0` 可只取 count；可用 GraphQL alias 将当前可见目录的计数合并成一个请求。不要逐一查询整棵目录树的计数。

- 同一图片可能同时有解压文件和压缩包内副本。按服务器返回的原生目录归属显示，每个选定范围按图片 ID 去重；虚拟 zip 目录不能当作可扫描磁盘目录。
- 默认日期排序由服务器分页。文件名自然排序对选定范围拉轻量 ID/路径并排序，再按 ID 批量加载详情；不能只排序已加载的第一屏。`findImages(ids: ...)` 返回顺序需要在客户端恢复。

## 隐藏目录与布尔筛选

目标版本不允许同一 filter 层级同时出现 `AND`、`OR` 或 `NOT` 多个布尔操作。将排除条件嵌入另一层：

```json
{
  "files_filter": {
    "parent_folder": {"value":["SCOPE_ID"],"modifier":"INCLUDES","depth":-1},
    "AND": {
      "NOT": {
        "parent_folder": {"value":["HIDDEN_ID"],"modifier":"INCLUDES","depth":-1},
        "OR": {"path":{"value":"^/media/other-hidden/","modifier":"MATCHES_REGEX"}}
      }
    }
  }
}
```

排除放在文件级，以免一个隐藏副本使另一可见副本也消失。计数和列表共用此过滤器。无原生 ID 时才用转义、锚定的路径正则；`/A` 不包含 `/AB`。

## 扫描和状态

- 配置路径读取 `excludeVideo` 与 `excludeImage`；任一类型允许的根目录都应可扫描，不能误拒绝图片专用根。
- 提交前重读配置并验证路径边界，拒绝相对路径和 `..`。不执行清理或删除。
- 扫描提交先检查已有队列；重复点击不重复建任务。连接中断可能只是提交响应丢失，保持“状态待确认”并核对，不能立即再次提交。
- 任务 ID 按服务器持久化；切服或页面销毁后丢弃旧响应。扫描完成刷新视频、图片和目录索引/计数，状态提示可展开或收起。
- 不把真实服务端凭据、目录和联调快照放入这份参考资料；运行时从当前已授权配置读取。
