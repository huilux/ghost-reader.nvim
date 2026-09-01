# Lua 语言快速参考

本文档是与本插件代码注释配套的 Lua 语言速查手册。阅读代码时遇到不熟悉的语法可以在这里查找。

---

## 1. 变量与作用域

```lua
x = 10           -- 全局变量（不推荐，容易污染命名空间）
local x = 10     -- 局部变量（推荐，作用域限于当前块）
```

Lua 中**默认是全局变量**，必须用 `local` 声明局部变量。几乎所有情况都应该用 `local`。

---

## 2. 表（Table）— Lua 唯一的复合数据结构

Lua 没有数组、字典、对象、类——这些全部用**表**来实现：

```lua
-- 数组（整数索引，从 1 开始！）
local arr = { "a", "b", "c" }
print(arr[1])    -- "a"（不是 "a"[0]！）

-- 字典（字符串键）
local dict = { name = "Alice", age = 30 }
print(dict.name)  -- "Alice"

-- 混合使用
local mix = { "first", key = "value", [10] = "tenth" }

-- 嵌套表
local nested = {
  reader = {
    renderer = "overlay",
    visible_blocks = 3,
  },
  keymaps = {
    global = {
      open = "<leader>rr",
      hide = "<Esc><Esc>",
    },
  },
}
```

### 关键操作

```lua
t.key = value         -- 设置/修改
t["key"] = value      -- 等价写法
t.key = nil           -- 删除键（设为 nil 即删除）
#t                    -- 获取数组部分的长度（只对连续整数索引有效）
```

---

## 3. 字符串模式（NOT 正则表达式！）

Lua 使用**自己的模式匹配系统**，不是正则表达式。关键区别：

| 正则表达式 | Lua 模式 | 说明 |
|-----------|----------|------|
| `\d` | `%d` | 数字，转义用 `%` 而非 `\` |
| `\w` | `%w` | 字母数字 |
| `\s` | `%S` | 空白 / 非空白（大写=取反） |
| `.` | `.` | 任意字符（相同） |
| `*` | `*` | 零次或多次（相同） |
| `+` | `+` | 一次或多次（相同） |
| `?` | `?` | 零次或一次（相同） |
| `\|` | 不支持 | 没有或运算符！ |
| `(...)` | `(...)` | 捕获组（相同） |
| `^` / `$` | `^` / `$` | 锚定（相同） |
| `\\.` | `%.` | 转义特殊字符用 `%` |

### 常用函数

```lua
s:match(pattern)         -- 返回匹配（有捕获组则返回捕获内容）
s:find(pattern)          -- 返回起止位置
s:gsub(pattern, repl)    -- 全局替换，返回 新字符串, 替换次数
s:gmatch(pattern)        -- 返回迭代器，用于 for...in
s:sub(i, j)              -- 子串（1-based，包含两端）
s:byte(i)                -- 第 i 个字节的数值
s:len() / #s             -- 字符串长度（字节数，非字符数）
s:lower() / s:upper()    -- 大小写转换
```

### 模式示例

```lua
-- 匹配文件扩展名
path:match("%.([^%.]+)$")
-- %.    = 字面量点号（. 在模式中是特殊字符，% 转义）
-- ()    = 捕获组
-- [^%.] = "不是点号"的字符
-- +     = 一个或多个
-- $     = 字符串末尾

-- 匹配 Markdown 标题
line:match("^(#+)%s+(.+)$")
-- ^     = 字符串开头
-- (#+)  = 一个或多个 # 号（捕获）
-- %s+   = 一个或多个空白
-- (.+)  = 其余内容（捕获）
-- $     = 字符串末尾
```

---

## 4. 循环

### 数值 for

```lua
for i = 1, 10 do ... end        -- 1 到 10
for i = 1, 10, 2 do ... end     -- 步长为 2
for i = 10, 1, -1 do ... end    -- 倒序
```

### ipairs — 有序索引遍历（数组）

```lua
for i, v in ipairs({ "a", "b", "c" }) do
  print(i, v)  -- 1 a, 2 b, 3 c
end
```

只遍历整数索引，从 1 开始直到第一个 `nil`。

### pairs — 所有键遍历（字典）

```lua
for k, v in pairs({ name = "Alice", age = 30 }) do
  print(k, v)  -- 顺序不确定
end
```

### for...in — 自定义迭代器

```lua
for line in f:lines() do ... end     -- 文件逐行读取
for match in str:gmatch(pat) do ... end  -- 逐个匹配
```

---

## 5. 函数

### 基本定义

```lua
function M.greet(name)
  return "Hello, " .. name
end
-- 等价于：
M.greet = function(name)
  return "Hello, " .. name
end
```

### 多返回值

Lua 函数可以返回多个值：

```lua
function divmod(a, b)
  return math.floor(a / b), a % b
end
local q, r = divmod(10, 3)  -- q=3, r=1
```

常见约定：返回 `result, err`，`err` 不为 nil 表示出错：
```lua
local book, err = bookshelf.open(path)
if err then ... end
```

### 匿名函数

```lua
vim.keymap.set("n", "j", function()
  -- 回调函数直接内联定义
end)
```

---

## 6. 方法调用语法（`:`）

Lua 的 `:` 是语法糖，自动将对象本身作为第一个参数传入：

```lua
-- 这两种写法完全等价：
f:read("*a")
f.read(f, "*a")

-- 定义方法时同理：
function M.open(path) ... end
-- M 会被隐式传给 self（如果用 : 定义的话）
```

本插件中 `f:read()`、`f:lines()`、`s:match()` 等都是方法调用。

---

## 7. pcall — 错误处理

```lua
local ok, result = pcall(some_function, arg1, arg2)
if ok then
  -- 成功，result 是函数返回值
else
  -- 失败，result 是错误消息字符串
end
```

`pcall` = "protected call"，相当于 try/catch。不会中断程序执行。

---

## 8. 常用标准库

### table 库

```lua
table.insert(t, value)           -- 在末尾插入
table.insert(t, pos, value)      -- 在指定位置插入
table.remove(t, pos)             -- 删除并返回指定位置的元素
table.sort(t)                    -- 默认升序排序
table.sort(t, function(a,b) ... end)  -- 自定义比较器
```

### string 库

```lua
string.format("%s %d", "hello", 42)  -- 格式化（类似 C 的 sprintf）
string.format("%%")                   -- %% 输出字面量 %
```

### math 库

```lua
math.floor(x)    -- 向下取整
math.min(a, b)   -- 最小值
math.max(a, b)   -- 最大值
math.random(n)   -- 1 到 n 的随机整数
math.random(a,b) -- a 到 b 的随机整数
```

### io 库

```lua
local f = io.open(path, "r")   -- 打开文件读 ("r"), 写 ("w"), 追加 ("a")
if f then
  local content = f:read("*a")  -- 读取全部内容
  for line in f:lines() do ... end  -- 逐行读取
  f:close()                     -- 关闭文件
end
```

### os 库

```lua
os.time()       -- 当前 Unix 时间戳（秒）
```

---

## 9. 运算符

```lua
-- 字符串拼接
"hello" .. " world"   -- "hello world"

-- 长度运算符
#arr                   -- 数组长度
#str                   -- 字符串字节长度

-- 逻辑运算符
-- Lua 用单词，不是符号！
and    -- 逻辑与（不是 &&）
or     -- 逻辑或（不是 ||）
not    -- 逻辑非（不是 !）

-- 特殊值
nil    -- 空/未定义
true / false

-- 注意：0 和空字符串是 truthy！
if 0 then ... end      -- 这会执行！
if "" then ... end     -- 这也会执行！
```

---

## 10. 模块模式

Lua 没有内置的模块系统。社区约定使用"表 + return"模式：

```lua
-- my_module.lua
local M = {}          -- 创建一个空表作为模块

function M.hello()    -- 在表上定义函数
  print("hello")
end

return M              -- 返回这个表
```

```lua
-- 其他文件中使用
local my_module = require("my_module")  -- require() 返回那个表
my_module.hello()    -- 调用模块上的函数
```

---

## 插件架构总览

```
plugin/ghost-reader.lua          ← 启动时自动加载，注册 :GhostReader 等命令
        │
        │ require()
        ▼
lua/ghost-reader/init.lua        ← 主模块：setup()、open()、open_statusline()、close()、toc()
        │
        ├── config.lua           ← 默认配置 + 深度合并
        ├── utils.lua            ← 工具函数（文件检测、格式识别）
        ├── history.lua          ← 书籍历史记录（最近 20 本）
        │
        ├── bookshelf/           ← 书籍解析
        │   ├── init.lua         ← 格式检测 + 调度到对应解析器
        │   ├── parser_txt.lua   ← 纯文本解析
        │   ├── parser_md.lua    ← Markdown 解析
        │   └── parser_epub.lua  ← EPUB 解析（解压 + HTML 提取）
        │
        ├── reader/              ← 阅读逻辑
        │   ├── navigate.lua     ← 翻页/翻章导航逻辑
        │   └── progress.lua     ← 阅读进度保存/加载
        │
        ├── renderer/            ← 内容渲染
        │   ├── init.lua         ← 调度器
        │   ├── overlay.lua      ← 真实 buffer 上的虚拟行覆盖
        │   ├── mirror.lua       ← buffer 伪装回退（light/strong）
        │   └── statusline.lua    ← 状态栏浮窗
        │
```

### 数据流

```
用户打开书籍
    │
    ▼
bookshelf.open(path)          检测格式 → 调用对应解析器 → 返回 book 对象
    │
    ▼
ghost-reader.open(path)       选择书籍 / 恢复会话 → 交给 session
    │
    ▼
session.start(path)           创建会话 → 选择 renderer → 渲染内容
    │
    ▼
用户阅读（j/k 内容跳转）
    │
    ▼
navigate.next_page(state)     更新阅读位置 → 重新渲染
    │
    ▼
progress.save(book, state)    保存进度到 JSON 文件
```
