# ghost-reader.nvim

Neovim 隐匿式电子书阅读器，支持 EPUB/TXT/Markdown 格式，在终端里伪装成代码偷偷看书。

## 两种阅读模式

### overlay（默认模式）

在真实 buffer 上方叠加虚拟内容，不改写文件内容、文件名或状态栏。每次只显示少量书本文字，让阅读尽量贴近正常编辑。

### statusline（状态栏模式）

在屏幕底部创建一个浮动窗口，每次显示一行文字。不影响主 buffer，正常写代码的同时看书。

支持自动翻页和手动翻页两种子模式。

## 快捷键体系

快捷键分为两层：**全局入口**和**阅读模式专用**。

### 全局入口快捷键

在任何 buffer 下均可使用，配置在 nvim 插件配置中（如 lazy.nvim 的 `keys`）。

| 快捷键 | 功能 |
|--------|------|
| `<leader>rr` | 打开或恢复阅读 |
| `<leader>rs` | 打开状态栏阅读 |
| `<leader>rm` | 进入或退出阅读控制层 |
| `<leader>rh` | 隐藏或恢复阅读 |
| `<leader>rt` | 目录 |
| `<leader>rq` | 关闭当前会话 |

`<leader>rr` 的智能行为：

| 当前状态 | 按下后 |
|----------|--------|
| 没在阅读 | 弹出书籍选择菜单 |
| 已在阅读 | 打开当前会话或恢复显示 |

### 全屏模式快捷键（buffer-local）

仅在阅读 buffer 内生效，切走后不干扰正常操作。

| 快捷键 | 功能 |
|--------|------|
| `j` | 跳到下一个内容行（自动翻页） |
| `k` | 跳到上一个内容行（自动翻页） |
| `]]` | 下一章 |
| `[[` | 上一章 |
| `t` | 打开目录跳转 |
| `g%` | 显示阅读进度 |
| `gh` | 隐藏当前会话 |
| `q` | 关闭当前会话 |
| `?` | 显示按键帮助 |
| `<Esc>` | 退出控制层 |

### 状态栏模式快捷键（buffer-local）

仅在状态栏模式激活的 buffer 内生效。

| 快捷键 | 功能 |
|--------|------|
| `j` | 下一行/段 |
| `k` | 上一行/段 |
| `a` | 切换自动/手动模式 |
| `+` | 加速 |
| `-` | 减速 |
| `q` | 关闭当前会话 |
| `<Esc>` | 退出控制层 |

## 安装

```lua
-- lazy.nvim
return {
  'huilux/ghost-reader.nvim',
  cmd = { 'GhostReader', 'GhostReaderClose', 'GhostReaderControl', 'GhostReaderHide', 'GhostReaderStatusline', 'GhostReaderToc' },
  keys = {
    { '<leader>rr', function() require('ghost-reader').open() end, desc = '打开/恢复阅读' },
    { '<leader>rs', function() require('ghost-reader').open_statusline() end, desc = '打开状态栏阅读' },
    { '<leader>rq', function() require('ghost-reader').close() end, desc = '关闭阅读' },
  },
  opts = {
    reader = {
      renderer = 'overlay',
      visible_blocks = 3,
    },
    statusline = {
      interval = 3000,  -- 自动翻页间隔（毫秒）
      autoplay = true,
      page_step = 5,
    },
    stealth = {
      hide_on_focus_lost = true,
      silent = true,
    },
  },
}
```

## 命令

| 命令 | 功能 |
|------|------|
| `:GhostReader [path]` | 打开书籍（无参数弹出选择） |
| `:GhostReaderClose` | 关闭阅读 |
| `:GhostReaderControl` | 进入或退出阅读控制层 |
| `:GhostReaderHide` | 隐藏或恢复当前会话 |
| `:GhostReaderToc` | 打开目录 |
| `:GhostReaderStatusline [path]` | 以状态栏模式打开 |

## 功能

- **书籍历史**：自动记录最近打开的书籍，`<leader>rr` 直接选择
- **进度记忆**：自动保存/恢复章节和行位置
- **会话控制**：`<leader>rm` 进入控制层，`<leader>rh` 隐藏或恢复
- **多格式**：EPUB（需系统有 unzip）、TXT、Markdown
- **长文本换行**：overlay 模式按可视区域宽度展示，状态栏模式按屏幕宽度分段显示
