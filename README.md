# ghost-reader.nvim

Neovim 隐匿式电子书阅读器，支持 EPUB/TXT/Markdown，在终端里像正常写代码一样看书。

这个插件有两个面向用户的阅读模式：

- overlay 是默认模式，使用真实 buffer 上的 extmark 虚拟行显示内容，不改写文件内容、文件名、`modified` 状态或 undo 历史。
- statusline 是底部的一行浮窗，一次显示一段文本，适合边写代码边低调阅读。
- 当 overlay 不能直接接管目标窗口时，插件会自动回退到 mirror。

视觉上的伪装只是界面层面的效果，不是安全边界。

## 快捷键

插件把快捷键分成全局入口和阅读控制层两部分。

插件加载后，可以在任何 buffer 使用以下全局快捷键：

| 快捷键       | 功能                 |
| ------------ | -------------------- |
| `<leader>rr` | 打开阅读会话         |
| `<leader>rs` | 打开 statusline 阅读 |
| `<leader>rm` | 进入或退出阅读控制层 |
| `<Esc><Esc>` | 隐藏或恢复当前会话   |
| `<leader>rt` | 打开目录             |
| `<leader>rq` | 关闭当前会话         |

阅读控制层在阅读 buffer 内生效，overlay、mirror 和 statusline 使用同一组语义：

| 快捷键  | 功能         |
| ------- | ------------ |
| `j`     | 下一段内容   |
| `k`     | 上一段内容   |
| `<C-f>` | 下一页       |
| `<C-b>` | 上一页       |
| `]]`    | 下一章       |
| `[[`    | 上一章       |
| `t`     | 目录         |
| `g%`    | 进度         |
| `q`     | 关闭当前会话 |
| `?`     | 帮助         |

statusline 模式还支持：

| 快捷键 | 功能          |
| ------ | ------------- |
| `a`    | 切换自动/手动 |
| `+`    | 加快自动翻页  |
| `-`    | 减慢自动翻页  |

## 安装

```lua
return {
  "huilux/ghost-reader.nvim",
  cmd = {
    "GhostReader",
    "GhostReaderStatusline",
  },
  keys = {
    { "<leader>rr", function() require("ghost-reader").open() end, desc = "Open reading" },
    { "<leader>rs", function() require("ghost-reader").open_statusline() end, desc = "Open statusline reader" },
  },
  opts = {},
}
```

这里的 `keys` 属于 lazy.nvim，只负责在插件尚未加载时提供两个“打开阅读”的入口。插件加载后，其他全局快捷键以及阅读控制层快捷键由 Ghost Reader 根据内置默认值注册，因此不需要在 `keys` 和 `opts.keymaps` 中重复写一遍。

## 命令

| 命令                            | 功能                           |
| ------------------------------- | ------------------------------ |
| `:GhostReader [path]`           | 打开书籍；无参数时选择历史记录 |
| `:GhostReaderClose`             | 关闭当前会话                   |
| `:GhostReaderControl`           | 进入或退出阅读控制层           |
| `:GhostReaderHide`              | 硬隐藏或恢复当前会话           |
| `:GhostReaderStatusline [path]` | 以 statusline 模式打开         |
| `:GhostReaderToc`               | 打开目录                       |

## 阅读模式

overlay：

- 默认模式。
- 用 extmark 和 `virt_lines` 把内容画到真实 buffer 上方。
- 适合最像“正常编辑”的伪装方式。

statusline：

- 底部一行浮窗。
- 支持自动翻页和手动翻页。
- 长文本会按窗口宽度切段显示。

mirror：

- overlay 受限时的自动回退。
- 使用匿名 scratch buffer 作为稳定替身。

## Stealth 事件

当 `stealth` 选项开启时，插件会根据环境自动隐藏或恢复当前会话。常见的自动隐藏来源包括：

- 切换到插入模式；
- 离开当前 buffer；
- 离开当前窗口；
- 失去焦点。

`<Esc><Esc>` 会在显示与硬隐藏之间切换。隐藏会退出控制层并恢复被接管的按键；恢复 overlay 或 mirror 时会重新进入控制层，恢复 statusline 时则保持控制层关闭。单击 `<Esc>` 保留 Neovim 的原生行为，控制层只由 `<leader>rm` 切换。

如果手动把 `keymaps.controls.exit_controls` 重新设为 `<Esc>`，这个 buffer-local 前缀映射会优先于全局 `<Esc><Esc>`；请同时为隐藏功能改用不以 `<Esc>` 开头的按键。

## 配置

下面是完整配置参考，所有字段都可以省略。使用 lazy.nvim 时，请把 `setup({ ... })` 中的表内容放到插件规格的 `opts` 中；只有手动配置插件时才直接调用 `setup()`。`keymaps.global` 控制插件加载后的全局快捷键，`keymaps.controls` 和 `keymaps.statusline` 控制阅读会话中的 buffer-local 快捷键。如果修改 `global.open` 或 `global.statusline`，还应同步修改安装配置中 lazy.nvim 的对应 `keys`，保证首次按键能够加载插件。

```lua
require("ghost-reader").setup({
  reader = {
    renderer = "overlay",
    visible_blocks = 3,
    mirror_fallback = true,
  },
  statusline = {
    interval = 3000,
    autoplay = true,
    page_step = 5,
  },
  stealth = {
    hide_on_focus_lost = true,
    silent = true,
    overlay = {
      hide_on_insert = true,
      hide_on_buf_leave = true,
      hide_on_win_leave = true,
    },
  },
  paths = {
    cache_dir = vim.fn.stdpath("cache") .. "/ghost-reader/",
    data_dir = vim.fn.stdpath("data") .. "/ghost-reader/",
  },
  keymaps = {
    global = {
      open = "<leader>rr",
      statusline = "<leader>rs",
      control = "<leader>rm",
      hide = "<Esc><Esc>",
      toc = "<leader>rt",
      close = "<leader>rq",
    },
    controls = {
      next_content = "j",
      prev_content = "k",
      next_page = "<C-f>",
      prev_page = "<C-b>",
      next_chapter = "]]",
      prev_chapter = "[[",
      toc = "t",
      progress = "g%",
      hide = false,
      close = "q",
      help = "?",
      exit_controls = false,
    },
    statusline = {
      toggle_auto = "a",
      faster = "+",
      slower = "-",
    },
  },
})
```

## 需求

- Neovim 0.10+
- `unzip` 仅用于 EPUB 支持
- Plenary 只用于测试

## 排查

- 如果 `:GhostReaderStatusline` 没有弹出浮窗，先确认当前窗口没有被其他插件强制改写。
- 如果 overlay 不工作，插件会自动回退到 mirror。
- 如果你看不到任何内容，检查 `visible_blocks`、窗口宽度，以及当前文件是否真的可读。
