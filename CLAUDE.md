# ghost-reader.nvim

Neovim 隐匿式电子书阅读器（EPUB/TXT/Markdown），mirror（默认）与 statusline 双模式。完整功能说明见 README.md。

## 开发

- 跑全部测试：`make test-all`；单文件：`make test FILE=test_session`
- 测试 runner 自检：`make test-runner-check`
- 测试基于 Plenary，仅测试需要它；EPUB 解析依赖系统 `unzip`

## 结构

- `lua/ghost-reader/session.lua` — 核心状态机（生命周期/可见性、dispatch 分发、进度保存）
- `lua/ghost-reader/renderer/` — mirror（含 mirror_layout 分布式布局）与 statusline 渲染器
- `lua/ghost-reader/bookshelf/` — txt / markdown / epub 解析器
- `lua/ghost-reader/config.lua` — 配置 schema 与默认值的唯一来源；README 的配置示例必须与此同步
- `lua/ghost-reader/keymaps.lua` — `<Plug>(GhostReader*)` 映射与 buffer-local 接管/恢复

## 约定

- 新功能遵循 TDD：先在 `tests/` 写失败测试，再实现
- 改配置项时同步 README 的配置参考和默认值
