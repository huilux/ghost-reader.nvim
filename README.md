# ghost-reader.nvim

Neovim 隐匿式电子书阅读器：支持 EPUB / TXT / Markdown，在终端里像正常写代码一样看书。

- **mirror**（默认）— buffer 阅读模式，书籍内容以注释形式的虚拟文本分散显示在当前文件上
- **statusline** — 状态栏上方的一行浮窗，一次显示一段文本

> 视觉上的伪装只是界面层面的效果，**不是安全边界**。

## 需求

| 依赖           | 用途             |
| -------------- | ---------------- |
| Neovim 0.10+   | 运行环境         |
| `unzip`        | 仅 EPUB 支持需要 |
| [plenary.nvim] | 仅运行测试需要   |

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

`keys` 属于 lazy.nvim，只负责在插件尚未加载时提供统一入口。插件加载后，其他全局快捷键和阅读键由 Ghost Reader 自动注册，不需要在 `keys` 和 `opts.keymaps` 中重复配置。

## 快速开始

1. 按 `<leader>rr`（或执行 `:GhostReader`）
2. 在弹出的列表中选择书籍，或选择「+ 输入新路径...」打开新书
3. 选择 `mirror` 或 `statusline` 模式，开始阅读
4. 随时按 `<Esc><Esc>` 硬隐藏，再按一次恢复；按 `q` 关闭会话

阅读进度自动保存，重新打开同一本书会从上次位置继续。

## 命令

| 命令                            | 功能                       |
| ------------------------------- | -------------------------- |
| `:GhostReader [path]`           | 选择书籍（可选）和阅读模式 |
| `:GhostReaderStatusline [path]` | 以 statusline 模式打开     |
| `:GhostReaderToc`               | 打开目录                   |
| `:GhostReaderHide`              | 硬隐藏或恢复当前会话       |
| `:GhostReaderClose`             | 关闭当前会话               |

## 快捷键

插件只有「阅读可见」和「硬隐藏」两种操作状态：阅读可见时接管下列阅读键，硬隐藏后恢复原有映射。没有配置成阅读键的按键始终保留 Neovim 原生行为。

### 全局（插件加载后生效）

| 快捷键       | 功能                 |
| ------------ | -------------------- |
| `<leader>rr` | 选择书籍和阅读模式   |
| `<Esc><Esc>` | 硬隐藏或恢复当前会话 |
| `<leader>rt` | 打开目录             |
| `<leader>rq` | 关闭当前会话         |

### 阅读键（mirror 与 statusline 通用，阅读可见时生效）

| 快捷键  | 功能                             |
| ------- | -------------------------------- |
| `j`     | 下一条阅读行                     |
| `k`     | 上一条阅读行                     |
| `<C-f>` | 下一页                           |
| `<C-b>` | 上一页                           |
| `]]`    | 下一章                           |
| `[[`    | 上一章                           |
| `t`     | 目录                             |
| `g%`    | 进度                             |
| `q`     | 关闭当前会话                     |
| `?`     | 帮助（显示当前模式生效的快捷键） |

### statusline 专属

| 快捷键 | 功能                |
| ------ | ------------------- |
| `a`    | 切换自动 / 手动翻页 |
| `+`    | 加快自动翻页        |
| `-`    | 减慢自动翻页        |

以上按键均可通过 `keymaps` 配置覆盖或禁用（设为 `false`），见[配置](#配置)。

## 阅读模式

### mirror

- 书籍内容以当前语言的注释形式显示在当前真实活动文件上，顶部 Tab、文件名和当前活动 buffer 保持不变。
- 内容按区域分散到整个 buffer，像代码中的注释一样形成多个阅读块；布局只在可见区域绘制。
- 使用窗口局部的临时虚拟文本，不会改写原代码、modified 状态、undo、LSP、诊断或其他窗口中的同一 buffer。
- 内容块会避开折叠中的行；打开或关闭折叠会触发重新布局。
- `j` / `k` 把光标跳到下一个 / 上一个内容块的锚点，跨越当前批次边界时自动加载下一批或上一批内容。
- 切换 buffer 或窗口时，阅读跟随当前活动文件；硬隐藏会保存并恢复进入阅读前的代码光标和窗口视图。
- mirror 可见时进入插入模式会暂时移除阅读内容，退出插入模式后重新捕获代码视图并刷新布局；窗口尺寸改变也会触发重新布局。

### statusline

- 位于 Vim / lualine 原生状态栏上方，不遮挡原生状态信息。
- 支持自动翻页和手动翻页，`a` 立即切换。
- 行首 `▶` 表示自动阅读，`‖` 表示手动阅读。
- `+` / `-` 调整自动翻页间隔（每次 0.5 秒，范围 0.5–15 秒），并提示当前生效的秒数。
- 长文本按窗口宽度切段显示。
- 阅读可见时，阅读映射跟随当前 buffer。

## 配置

所有字段都可以省略。使用 lazy.nvim 时，把 `setup({ ... })` 中的表内容放到插件规格的 `opts`；只有手动配置时才直接调用 `setup()`。

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
    silent = false,
  },
  paths = {
    cache_dir = vim.fn.stdpath("cache") .. "/ghost-reader/",
    data_dir = vim.fn.stdpath("data") .. "/ghost-reader/",
  },
  keymaps = {
    -- 见下方「快捷键配置」
  },
})
```

### reader

| 参数              | 类型                         | 默认值     | 说明         |
| ----------------- | ---------------------------- | ---------- | ------------ |
| `reader.renderer` | `"mirror"` \| `"statusline"` | `"mirror"` | 默认阅读模式 |

### buffer

| 参数                        | 类型   | 默认值 | 说明                                                 |
| --------------------------- | ------ | ------ | ---------------------------------------------------- |
| `buffer.layout`             | table  | 见下表 | mirror 内容块布局参数                                |
| `buffer.virt_text_priority` | 正整数 | `1000` | 虚拟文本绘制优先级；与其他插件的行级文字冲突时可调高 |

`buffer.layout` 把真实 buffer 划分为多个区域并限制内容块数量：

| 参数                    | 类型     | 默认值 | 说明                       |
| ----------------------- | -------- | ------ | -------------------------- |
| `region_lines`          | 正整数   | `50`   | 区域大小（行数）           |
| `max_blocks_per_region` | 正整数   | `3`    | 每个区域最多的内容块数     |
| `max_lines_per_block`   | 正整数   | `2`    | 每个块最多显示的行数       |
| `min_gap_lines`         | 非负整数 | `6`    | 相邻内容块之间的最小空行数 |
| `max_total_blocks`      | 正整数   | `12`   | 一批内容的总块数上限       |
| `edge_padding`          | 非负整数 | `2`    | buffer 首尾保留的空白行数  |

约束：`max_lines_per_block + edge_padding × 2` 不能超过 `region_lines`。

### statusline

| 参数                   | 类型    | 默认值 | 说明                   |
| ---------------------- | ------- | ------ | ---------------------- |
| `statusline.interval`  | 正整数  | `3000` | 自动翻页间隔（毫秒）   |
| `statusline.autoplay`  | boolean | `true` | 打开后是否自动翻页     |
| `statusline.page_step` | 正整数  | `5`    | 翻页一次跨越的阅读段数 |

### stealth

| 参数                         | 类型    | 默认值  | 说明                                                             |
| ---------------------------- | ------- | ------- | ---------------------------------------------------------------- |
| `stealth.hide_on_focus_lost` | boolean | `true`  | 编辑器失去焦点时自动硬隐藏                                       |
| `stealth.silent`             | boolean | `false` | 抑制所有 `[ghost-reader]` 提示消息（进度、帮助、翻页间隔提示等） |

### paths

| 参数              | 类型   | 默认值                                 | 说明                       |
| ----------------- | ------ | -------------------------------------- | -------------------------- |
| `paths.cache_dir` | string | `stdpath("cache") .. "/ghost-reader/"` | 缓存目录                   |
| `paths.data_dir`  | string | `stdpath("data") .. "/ghost-reader/"`  | 阅读进度与书籍历史存储目录 |

### 快捷键配置

`keymaps.global` 控制插件加载后的全局快捷键；`keymaps.reader` 和 `keymaps.statusline` 控制阅读可见时的 buffer-local 快捷键。值为按键字符串，或 `false` 表示禁用该键。修改 `global.open` 时应同步修改 lazy.nvim 的 `keys`，保证首次按键能够加载插件。

| 参数                             | 默认键          | 功能               | 作用域          |
| -------------------------------- | --------------- | ------------------ | --------------- |
| `keymaps.global.open`            | `<leader>rr`    | 打开书籍和模式选择 | 全局            |
| `keymaps.global.hide`            | `<Esc><Esc>`    | 硬隐藏 / 恢复      | 全局            |
| `keymaps.global.toc`             | `<leader>rt`    | 目录               | 全局            |
| `keymaps.global.close`           | `<leader>rq`    | 关闭会话           | 全局            |
| `keymaps.reader.next_content`    | `j`             | 下一条阅读行       | 阅读可见        |
| `keymaps.reader.prev_content`    | `k`             | 上一条阅读行       | 阅读可见        |
| `keymaps.reader.next_page`       | `<C-f>`         | 下一页             | 阅读可见        |
| `keymaps.reader.prev_page`       | `<C-b>`         | 上一页             | 阅读可见        |
| `keymaps.reader.next_chapter`    | `]]`            | 下一章             | 阅读可见        |
| `keymaps.reader.prev_chapter`    | `[[`            | 上一章             | 阅读可见        |
| `keymaps.reader.toc`             | `t`             | 目录               | 阅读可见        |
| `keymaps.reader.progress`        | `g%`            | 进度               | 阅读可见        |
| `keymaps.reader.hide`            | `false`（禁用） | 硬隐藏             | 阅读可见        |
| `keymaps.reader.close`           | `q`             | 关闭会话           | 阅读可见        |
| `keymaps.reader.help`            | `?`             | 帮助               | 阅读可见        |
| `keymaps.statusline.toggle_auto` | `a`             | 切换自动 / 手动    | statusline 可见 |
| `keymaps.statusline.faster`      | `+`             | 加快自动翻页       | statusline 可见 |
| `keymaps.statusline.slower`      | `-`             | 减慢自动翻页       | statusline 可见 |

### 旧配置迁移

- `buffer.preset` 会被静默移除，不产生任何效果，迁移后应删除。
- `buffer.style` / `buffer.light` / `buffer.strong` 仍可用于兼容迁移：未配置 `buffer.layout` 时，会按旧样式换算出等价的 `layout`。新配置建议只使用 `buffer.layout`。

## 进度与历史

- 阅读进度自动保存到 `paths.data_dir`，重新打开同一本书会从上次位置继续；`g%` 随时查看当前章节、行数和总进度百分比。
- `<leader>rr` 的书籍选择列表来自持久化的阅读历史，也可以在列表末尾选择「+ 输入新路径...」打开其他书。

## Stealth 事件

- `stealth.hide_on_focus_lost` 开启时，编辑器失去焦点会自动硬隐藏当前会话。
- `<Esc><Esc>` 在显示与硬隐藏之间切换；硬隐藏会恢复被接管的原始映射，恢复后阅读映射立即重新生效。单击 `<Esc>` 保留 Neovim 原生行为。
- mirror 或 statusline 可见时切换 buffer 或窗口，阅读标记 / 浮窗和快捷键跟随当前文件；进入 terminal、help 等特殊 buffer 时 mirror 会暂时硬隐藏。

## 排查

| 现象                                  | 检查方向                                                                       |
| ------------------------------------- | ------------------------------------------------------------------------------ |
| `:GhostReaderStatusline` 没有弹出浮窗 | 当前窗口是否被其他插件强制改写                                                 |
| mirror 中看不到内容                   | 当前窗口是否有足够的可用 buffer 行；布局限制是否过于严格；当前文件是否真的可读 |
| `j` / `k` 没有移动到阅读内容          | mirror 是否仍处于可见状态——它们只在阅读可见时绑定，并按内容块而不是代码行移动  |
| 当前行出现其他插件的行级文字          | 提高 `buffer.virt_text_priority`；视觉伪装仍不是安全边界                       |

[plenary.nvim]: https://github.com/nvim-lua/plenary.nvim
