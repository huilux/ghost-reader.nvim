# Neovim/Vim 基础知识

本文档为没有 Vim 背景的读者准备，介绍理解本插件所需的核心概念。

---

## 1. Buffer / Window / Tab

Vim/Neovim 中有三个核心概念，初学者经常混淆：

| 概念 | 说明 | 类比 |
|------|------|------|
| **Buffer** | 文件在内存中的实例。一个 Buffer 对应一个打开的文件（或临时内容）。 | 浏览器的"标签页内容" |
| **Window** | 查看 Buffer 的视口。一个 Window 只能显示一个 Buffer，但多个 Window 可以显示同一个 Buffer。 | 浏览器的"分屏" |
| **Tab** | Window 的容器。一个 Tab 可以包含多个 Window（分屏布局）。 | 浏览器的"窗口" |

关键区别：
- 你可以打开 10 个文件（10 个 Buffer），但只有 1 个 Window 来查看。
- 关闭一个 Window 不等于关闭它显示的 Buffer。
- Buffer 可以"隐藏"（不显示在任何 Window 中）但仍然存在。

本插件大量操作 Buffer：创建新的 Buffer 来显示书籍内容，并通过控制层与隐藏行为切换阅读状态。

---

## 2. 模式系统（Modes）

Vim 是一个**模态编辑器**，意味着按键的含义取决于当前所处的模式：

| 模式 | 用途 | 进入方式 |
|------|------|----------|
| **Normal** | 浏览和操作文本（移动光标、删除、复制等）。这是 Vim 的默认模式。 | 按 `Esc` |
| **Insert** | 输入文本，行为类似普通编辑器。 | 按 `i`、`a`、`o` 等 |
| **Visual** | 选择文本区域。 | 按 `v`（字符）、`V`（行）、`Ctrl+v`（块） |
| **Command-line** | 输入命令（如 `:w` 保存、`:q` 退出）。 | 输入 `:` |

本插件的键映射几乎全部绑定在 Normal 模式（`"n"`），因为阅读时不需要编辑文本。

---

## 3. 键映射（Keymaps）

键映射让你把按键序列绑定到特定操作。

### 模式前缀

```lua
vim.keymap.set("n", "J", action)   -- "n" = Normal 模式
vim.keymap.set("i", "jj", "<Esc>") -- "i" = Insert 模式
vim.keymap.set("v", "J", action)   -- "v" = Visual 模式
```

常用模式缩写：
- `"n"` — Normal
- `"i"` — Insert
- `"v"` — Visual
- `"x"` — Visual Line（行选择）
- `"s"` — Select
- `"c"` — Command-line

### Buffer 局部键映射

```lua
vim.keymap.set("n", "J", action, { buffer = buf })
```

`{ buffer = bufnr }` 使映射仅在特定 Buffer 中生效。当该 Buffer 被删除时，映射自动清理。
本插件使用此机制：阅读 Buffer 中的 `j`/`k`、`<C-f>`/`<C-b>` 和相关控制键只在阅读时有效。

### Leader Key

Leader Key 是一个"前缀键"，用于避免快捷键冲突：

```lua
vim.g.mapleader = " "   -- 设空格为 Leader 键
vim.keymap.set("n", "<leader>ff", action)  -- 实际按键：空格+f+f
```

`<leader>` 在映射字符串中会被替换为实际的 Leader 键值。如果你的 Leader 是空格，`<leader>ff` 就是 `空格+f+f`。

---

## 4. 插件目录结构

Neovim 插件遵循约定的目录结构：

```
my-plugin/
├── plugin/        ← 启动时自动加载（source），用于注册命令/自动命令
├── lua/           ← 通过 require() 按需加载，放业务逻辑
│   └── my-plugin/
│       ├── init.lua
│       └── ...
├── doc/           ← 帮助文档（:help my-plugin）
└── after/         ← 在其他插件之后加载的覆盖
```

关键区别：
- **`plugin/`** 中的 `.lua` 文件在 Neovim 启动时自动执行（类似 Vim 的 `source`）。适合注册命令，但不应该放重型逻辑。
- **`lua/`** 中的文件只在 `require()` 调用时才加载。这是**懒加载**——只有用户真正触发功能时才加载代码。

`require("ghost-reader.utils")` 的路径解析规则：
- 将 `.` 替换为目录分隔符 `/`
- 在 `runtimepath` 的 `lua/` 目录下查找
- 所以 `require("ghost-reader.utils")` → 查找 `lua/ghost-reader/utils.lua`

---

## 5. Neovim API 体系

Neovim 提供多个命名空间来访问不同层级的功能：

### `vim.api` — 核心编辑器 API

最底层也是最强大的 API，直接操作 Buffer、Window、Tab、Autocmd 等。

```lua
vim.api.nvim_create_buf(false, true)          -- 创建 Buffer
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines) -- 设置 Buffer 内容
vim.api.nvim_open_win(buf, false, config)     -- 创建浮动窗口
vim.api.nvim_create_user_command("Cmd", fn, opts) -- 注册命令
vim.api.nvim_create_autocmd("BufEnter", opts) -- 注册自动命令
```

### `vim.fn` — Vimscript 函数桥接

调用 Vimscript 内置函数。注意：返回值可能是整数 0/1（而非布尔值）。

```lua
vim.fn.filereadable(path)     -- 返回 0 或 1
vim.fn.expand("~/.config")    -- 展开路径
vim.fn.stdpath("cache")       -- 获取缓存目录
vim.fn.timer_start(ms, fn)    -- 定时器
vim.fn.fnamemodify(path, ":t") -- 路径修饰（:t=文件名, :h=目录, :r=去扩展名）
```

### `vim.o` / `vim.bo` / `vim.wo` — 选项访问

```lua
vim.o.columns          -- 全局选项：终端列数
vim.o.statusline       -- 全局选项：状态栏格式

vim.bo[buf].filetype   -- Buffer 局部选项：文件类型
vim.bo[buf].buftype    -- Buffer 局部选项：Buffer 类型

vim.wo[win].wrap       -- Window 局部选项：是否换行
vim.wo[win].winhl      -- Window 局部选项：高亮映射
```

`vim.o` = 全局，`vim.bo` = Buffer 局部，`vim.wo` = Window 局部。

### `vim.g` / `vim.b` / `vim.w` / `vim.t` / `vim.v` / `vim.env` — 变量作用域

| 命名空间 | 作用域 | 说明 |
|----------|--------|------|
| `vim.g` | 全局 (`g:`) | 跨 Buffer 共享的全局变量 |
| `vim.b` | Buffer (`b:`) | 仅在当前 Buffer 中可见 |
| `vim.w` | Window (`w:`) | 仅在当前 Window 中可见 |
| `vim.t` | Tab (`t:`) | 仅在当前 Tab 中可见 |
| `vim.v` | Vim 内置 (`v:`) | Vim 预定义变量（如 `v:true`、`v:null`） |
| `vim.env` | 环境变量 | 系统环境变量 |

### 其他常用命名空间

```lua
vim.keymap.set(mode, lhs, rhs, opts)  -- 键映射
vim.ui.select(items, opts, on_choice)  -- 选择对话框
vim.ui.input(opts, on_choice)          -- 输入对话框
vim.notify(msg, level)                 -- 通知
vim.json.encode(data) / vim.json.decode(str)  -- JSON
vim.deepcopy(tbl)                      -- 深拷贝表
vim.tbl_extend("force", t1, t2)        -- 合并表
vim.system({ "cmd", "args" }):wait()   -- 运行外部命令（0.10+）
vim.loop.fs_stat(path)                 -- 文件系统操作（libuv）
```

---

## 6. Buffer 生命周期

### 创建 Buffer

```lua
local buf = vim.api.nvim_create_buf(listed, scratch)
-- listed: 是否出现在 :ls 列表中
-- scratch: 是否为临时 Buffer（不关联文件）
```

### Buffer 类型

| 类型 | 说明 |
|------|------|
| 普通缓冲区 | 关联文件，可写入磁盘 |
| `"nofile"` | 不写入磁盘，适合临时显示 |
| `"scratch"` | 更临时的 Buffer，不记入历史 |
| `"terminal"` | 终端 Buffer |

本插件使用 `"nofile"` 类型，因为书籍内容不需要保存到磁盘。

### 操作 Buffer 内容

```lua
-- 读取所有行
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
-- 参数：buffer号, 起始行(0-based), 结束行(-1表示末尾), strict_indexing

-- 设置所有行（替换）
vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)

-- 设置 Buffer 名称（显示在状态栏/标签栏）
vim.api.nvim_buf_set_name(buf, "filename.lua")

-- 设置 Buffer 文件类型（控制语法高亮）
vim.bo[buf].filetype = "python"
```

---

## 7. 浮动窗口（Floating Window）

浮动窗口是 Neovim 的特色功能，可以在编辑器上方叠加一个临时窗口。

### 创建浮动窗口

```lua
local win = vim.api.nvim_open_win(buf, enter, {
  relative = "editor",   -- 定位参照："editor"=屏幕, "win"=当前窗口, "cursor"=光标
  width = 80,
  height = 1,
  row = 20,              -- 行位置（0-based）
  col = 0,               -- 列位置（0-based）
  style = "minimal",     -- 无边框、无行号、无折叠列
  focusable = false,     -- 光标不会进入此窗口
  zindex = 50,           -- 层叠顺序（越大越靠前）
})
```

- `enter = true` — 创建后立即将光标移入新窗口
- `enter = false` — 光标留在原窗口（本插件使用这种方式，让用户继续操作）

### 更新浮动窗口

```lua
vim.api.nvim_win_set_config(win, {
  relative = "editor",
  width = new_width,
  height = new_height,
  row = new_row,
  col = 0,
})
```

### 关闭浮动窗口

```lua
vim.api.nvim_win_close(win, true)  -- true = 强制关闭
```

---

## 8. 自动命令（Autocmd）

自动命令是事件驱动的：当某个事件发生时，自动执行指定的回调函数。

### 常用事件

| 事件 | 触发时机 |
|------|----------|
| `BufEnter` | 进入一个 Buffer 时 |
| `BufLeave` | 离开一个 Buffer 时 |
| `BufUnload` | Buffer 被卸载时 |
| `BufWinLeave` | Buffer 从 Window 中消失时 |
| `VimResized` | 终端窗口大小改变时 |
| `CursorHold` | 光标停留超过一定时间时 |

### 创建自动命令

```lua
-- 创建分组（防止重复注册）
local group = vim.api.nvim_create_augroup("my-plugin", { clear = true })

vim.api.nvim_create_autocmd("VimResized", {
  group = group,          -- 属于哪个分组
  buffer = buf,           -- 可选：仅在该 Buffer 中生效，Buffer 删除时自动清理
  callback = function()
    -- 事件触发时执行的代码
  end,
})
```

`{ clear = true }` 会先清除同名的所有已有自动命令，避免每次加载插件时重复注册。

---

## 9. runtimepath

`runtimepath` 是 Neovim 查找插件文件的搜索路径列表。

```lua
:echo &runtimepath
-- 输出类似：~/.config/nvim,/usr/share/nvim/runtime,~/.local/share/nvim/lazy/telescope.nvim,...
```

当一个插件被安装后（如通过 lazy.nvim、packer.nvim 等包管理器），它的根目录会被添加到 `runtimepath` 中。之后：
- `plugin/` 下的文件会在启动时自动执行
- `require()` 会在 `runtimepath` 的 `lua/` 目录中查找模块

---

## 10. `pcall` 模式

`pcall`（protected call）是 Lua 的"安全调用"，等价于其他语言的 try/catch：

```lua
local ok, result = pcall(some_function, arg1, arg2)
if ok then
  -- 成功，result 是返回值
else
  -- 失败，result 是错误消息
end
```

本插件中大量使用 `pcall` 来包裹可能失败的操作（如设置 Buffer 名称，因为名称可能重复导致报错）。
