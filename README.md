# ghost-reader.nvim

Neovim 隐匿式电子书阅读器，支持 EPUB/TXT/Markdown，在终端里像正常写代码一样看书。

这个插件有两个可选阅读模式：

- mirror 是默认的 buffer 阅读模式，使用虚拟文本覆盖在当前文件 buffer 上。
- statusline 是原生状态栏上方的一行浮窗，一次显示一段文本。

视觉上的伪装只是界面层面的效果，不是安全边界。

## 快捷键

插件只有“阅读可见”和“硬隐藏”两种操作状态。阅读可见时接管配置过的阅读键，硬隐藏后恢复原有映射。

插件加载后，可以在任何 buffer 使用以下全局快捷键：

| 快捷键       | 功能                 |
| ------------ | -------------------- |
| `<leader>rr` | 选择书籍和阅读模式   |
| `<Esc><Esc>` | 硬隐藏或恢复当前会话 |
| `<leader>rt` | 打开目录             |
| `<leader>rq` | 关闭当前会话         |

以下映射在阅读可见时生效，mirror 和 statusline 使用同一组语义。没有配置成阅读键的按键仍保留 Neovim 原生行为：

| 快捷键  | 功能         |
| ------- | ------------ |
| `j`     | 下一条阅读行 |
| `k`     | 上一条阅读行 |
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
  },
  opts = {},
}
```

这里的 `keys` 属于 lazy.nvim，只负责在插件尚未加载时提供统一入口。每次按 `<leader>rr` 都会依次选择书籍和 `mirror`/`statusline` 模式；重复打开会安全替换当前会话。插件加载后，其他全局快捷键和阅读键由 Ghost Reader 注册，不需要在 `keys` 和 `opts.keymaps` 中重复配置。

## 命令

| 命令                            | 功能                       |
| ------------------------------- | -------------------------- |
| `:GhostReader [path]`           | 选择书籍（可选）和阅读模式 |
| `:GhostReaderClose`             | 关闭当前会话               |
| `:GhostReaderHide`              | 硬隐藏或恢复当前会话       |
| `:GhostReaderStatusline [path]` | 以 statusline 模式打开     |
| `:GhostReaderToc`               | 打开目录                   |

## 阅读模式

statusline：

- 位于 Vim/lualine 原生状态栏上方，不遮挡原生状态信息。
- 支持自动翻页和手动翻页。
- 长文本会按窗口宽度切段显示。
- 阅读可见时，阅读映射会跟随当前 buffer。

mirror：

- 默认的 buffer 阅读模式。
- 书籍内容以当前语言的注释形式显示在当前真实活动文件上，顶部 Tab、文件名和当前活动 buffer 保持不变。
- 使用窗口局部的临时虚拟文本，不会改写原代码、modified 状态、undo、LSP、诊断或其他窗口中的同一 buffer。
- 内容会按区域分散到整个 buffer，像代码中的注释一样形成多个阅读块；布局只在可见区域绘制，并使用较高优先级避免被行级注释信息遮挡。
- `j/k` 会把光标跳到下一个/上一个内容块的锚点，跨越当前批次边界时会复用布局位置加载下一批或上一批内容。
- 切换 buffer 或窗口时，阅读会跟随当前活动文件；硬隐藏会保存并恢复进入阅读前的代码光标和窗口视图。
- 在 mirror 可见时进入插入模式会暂时移除阅读内容，退出插入模式后重新捕获代码视图并刷新布局；窗口尺寸改变也会触发重新布局。

## Stealth 事件

当 `stealth.hide_on_focus_lost` 开启时，编辑器失去焦点会自动硬隐藏当前会话。

`<Esc><Esc>` 会在显示与硬隐藏之间切换。硬隐藏会恢复被接管的原始映射；恢复后阅读映射立即重新生效。单击 `<Esc>` 保留 Neovim 的原生行为。mirror 或 statusline 可见时切换 buffer 或窗口，阅读标记/浮窗和快捷键会跟随当前文件；进入 terminal、help 等特殊 buffer 时 mirror 会暂时硬隐藏。

## 配置

下面是完整配置参考，所有字段都可以省略。使用 lazy.nvim 时，请把 `setup({ ... })` 中的表内容放到插件规格的 `opts` 中；只有手动配置插件时才直接调用 `setup()`。`keymaps.global` 控制插件加载后的全局快捷键，`keymaps.reader` 和 `keymaps.statusline` 控制阅读可见时的 buffer-local 快捷键。修改 `global.open` 时还应同步修改 lazy.nvim 的 `keys`，保证首次按键能够加载插件。

```lua
require("ghost-reader").setup({
  reader = {
    renderer = "mirror",
  },
  buffer = {
    layout = {
      region_lines = 50,
      max_blocks_per_region = 3,
      max_lines_per_block = 2,
      min_gap_lines = 6,
      max_total_blocks = 12,
      edge_padding = 2,
    },
    virt_text_priority = 1000,
  },
  statusline = {
    interval = 3000,
    autoplay = true,
    page_step = 5,
  },
  stealth = {
    hide_on_focus_lost = true,
    silent = true,
  },
  paths = {
    cache_dir = vim.fn.stdpath("cache") .. "/ghost-reader/",
    data_dir = vim.fn.stdpath("data") .. "/ghost-reader/",
  },
  keymaps = {
    global = {
      open = "<leader>rr",
      hide = "<Esc><Esc>",
      toc = "<leader>rt",
      close = "<leader>rq",
    },
    reader = {
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
    },
    statusline = {
      toggle_auto = "a",
      faster = "+",
      slower = "-",
    },
  },
})
```

`buffer.layout` 将真实 buffer 划分为多个区域，并限制每个区域的内容块数量。
内容块不会集中在光标附近：`region_lines` 是区域大小，
`max_blocks_per_region` 是每个区域最多的块数，`max_lines_per_block` 是每个块
最多显示的行数，`min_gap_lines` 是相邻块之间的最小空行数，
`max_total_blocks` 限制一批内容的总块数，`edge_padding` 保留 buffer 首尾的
空白行。除 `min_gap_lines` 和 `edge_padding` 允许为零外，其余布局数值均为正整数。

`virt_text_priority` 控制 mirror 虚拟文本的绘制优先级，默认值为 `1000`。
旧配置中的 `buffer.preset` 会被静默接受但不会产生任何效果；迁移后应删除它。
旧的 `style`、`light`、`strong` 配置仍可用于兼容迁移，但新配置建议只使用
`buffer.layout`。

## 需求

- Neovim 0.10+
- `unzip` 仅用于 EPUB 支持
- Plenary 只用于测试

## 排查

- 如果 `:GhostReaderStatusline` 没有弹出浮窗，先确认当前窗口没有被其他插件强制改写。
- 如果 mirror 中看不到内容，检查当前窗口是否有足够的可用 buffer 行、布局限制是否过于严格，以及当前文件是否真的可读。
- 如果 `j/k` 没有移动到阅读内容，确认 mirror 仍处于可见状态；它们只在阅读可见时绑定，并按内容块而不是代码行移动。
- 如果当前行出现其他插件的行级文字，mirror 会使用 `virt_text_priority` 和覆盖模式绘制；可适当提高该值，但视觉伪装仍不是安全边界。
