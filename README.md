# ghost-reader.nvim

Neovim 隐匿式电子书阅读器，支持 EPUB/TXT/Markdown 格式，在终端里伪装成代码偷偷看书。

## 两种阅读模式

### sparse_notes（全屏模式）

将书本文本伪装成代码中的 TODO/FIXME 注释，以真实打开的代码文件为骨架，书本文本稀疏穿插其中。整个 buffer 看起来像正常的代码文件。

### statusline（状态栏模式）

在屏幕底部创建一个浮动窗口，每次显示一行文字。不影响主 buffer，正常写代码的同时看书。

支持自动翻页和手动翻页两种子模式。

## 快捷键体系

快捷键分为两层：**全局入口**和**阅读模式专用**。

### 全局入口快捷键

在任何 buffer 下均可使用，配置在 nvim 插件配置中（如 lazy.nvim 的 `keys`）。

| 快捷键 | 功能 |
|--------|------|
| `<leader>go` | 智能入口：打开选书菜单 / 恢复阅读 |
| `<leader>gq` | 关闭全屏阅读 |
| `<leader>gt` | 目录（全屏模式下使用） |

`<leader>go` 的智能行为：

| 当前状态 | 按下后 |
|----------|--------|
| 没在阅读 | 弹出书籍选择菜单 |
| 全屏阅读切到了别的 buffer | 切回阅读 buffer |
| 状态栏阅读被老板键隐藏 | 恢复浮动窗口 |
| 已在阅读 | 无操作 |

### 全屏模式快捷键（buffer-local）

仅在阅读 buffer 内生效，切走后不干扰正常操作。

| 快捷键 | 功能 |
|--------|------|
| `J` | 下一页 |
| `K` | 上一页 |
| `]c` | 下一章 |
| `[c` | 上一章 |
| `<leader>gt` | 打开目录跳转 |
| `gp` | 显示阅读进度 |
| `<leader>gb` | 老板键：切回之前的工作 buffer |

### 状态栏模式快捷键（buffer-local）

仅在状态栏模式激活的 buffer 内生效。

| 快捷键 | 功能 |
|--------|------|
| `J` | 下一行/段 |
| `K` | 上一行/段 |
| `<leader>g+` | 加速（每次 -500ms） |
| `<leader>g-` | 减速（每次 +500ms） |
| `<leader>gm` | 切换自动/手动模式 |
| `<leader>gq` | 退出状态栏阅读 |
| `<leader>gb` | 老板键：隐藏浮动窗口 |

## 安装

```lua
-- lazy.nvim
return {
  'ghost-reader.nvim',
  dir = '~/workspace/Tools/hidden-reading',
  cmd = { 'GhostReader', 'GhostReaderClose', 'GhostReaderBoss', 'GhostReaderRestore', 'GhostReaderStatusline' },
  keys = {
    { '<leader>go', function() require('ghost-reader').select_book() end, desc = '打开/恢复阅读' },
    { '<leader>gq', function() require('ghost-reader').close() end,       desc = '关闭阅读' },
    { '<leader>gt', function() require('ghost-reader').toc() end,         desc = '目录跳转' },
  },
  opts = {
    boss_key = {
      keys = '<leader>gb',
      use_current_buffer = true,
      preset = 'random',
    },
    statusline = {
      interval = 3000,  -- 自动翻页间隔（毫秒）
      mode = "auto",    -- "auto" 自动 / "manual" 手动
    },
  },
}
```

## 命令

| 命令 | 功能 |
|------|------|
| `:GhostReader [path]` | 打开书籍（无参数弹出选择） |
| `:GhostReaderClose` | 关闭阅读 |
| `:GhostReaderStatusline [path]` | 以状态栏模式打开 |
| `:GhostReaderBoss` | 手动触发老板键 |
| `:GhostReaderRestore` | 手动恢复 |

## 功能

- **书籍历史**：自动记录最近打开的 20 本书，`<leader>go` 直接选择
- **进度记忆**：自动保存/恢复章节和行位置
- **老板键**：`<leader>gb` 一键隐藏，`<leader>go` 一键恢复
- **多格式**：EPUB（需系统有 unzip）、TXT、Markdown
- **长文本换行**：全屏模式自动 80 列换行，状态栏模式按屏幕宽度分段显示
