--[[
  stealth/presets.lua - 假代码预设模板

  角色：包含多套假代码模板（Go/Python/TSX/Lua/Rust）。
  当老板键触发时，从中选取一套显示在屏幕上，伪装成正在写代码。

  本文件80%以上是假代码数据，只有少量逻辑代码。
  假代码内容不需要逐行阅读，关注下方的 get/list/add 函数即可。

  本文件涉及的关键概念：
  - [Lua概念] 大型表字面量（模拟对象结构）
  - [Neovim API] vim.tbl_extend 表合并
  - [Lua概念] math.random 随机数
  - [Lua概念] pairs vs ipairs（遍历字典 vs 遍历数组）
  - [Lua概念] _ 变量占位符

  关联模块：被 stealth/init.lua 调用。
]]

local M = {}

-- 内置的假代码预设。每个预设是一个表，包含：
--   filetype = 文件类型（控制语法高亮）
--   path = 假的文件路径（显示在状态栏）
--   lines = 假代码的行数组
local builtins = {
  go_api = {
    filetype = "go",
    path = "internal/middleware/auth.go",
    lines = {
      "package middleware",
      "",
      'import (',
      '  "log"',
      '  "net/http"',
      '  "time"',
      ')',
      "",
      "type AuthMiddleware struct {",
      "  secretKey string",
      "  timeout   time.Duration",
      "}",
      "",
      "func NewAuthMiddleware(key string) *AuthMiddleware {",
      "  return &AuthMiddleware{",
      "    secretKey: key,",
      "    timeout:   30 * time.Second,",
      "  }",
      "}",
      "",
      "func (a *AuthMiddleware) Validate(next http.Handler) http.Handler {",
      "  return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {",
      '    token := r.Header.Get("Authorization")',
      '    if token == "" {',
      '      http.Error(w, "unauthorized", http.StatusUnauthorized)',
      "      return",
      "    }",
      "    claims, err := a.parseToken(token)",
      "    if err != nil {",
      '      log.Printf("auth error: %v", err)',
      '      http.Error(w, "forbidden", http.StatusForbidden)',
      "      return",
      "    }",
      '    r.Header.Set("X-User-ID", claims.UserID)',
      "    next.ServeHTTP(w, r)",
      "  })",
      "}",
      "",
      "func (a *AuthMiddleware) parseToken(token string) (*Claims, error) {",
      "  if len(token) < 10 {",
      '    return nil, fmt.Errorf("invalid token length")',
      "  }",
      "  return &Claims{UserID: token[7:]}, nil",
      "}",
    },
  },
  python_data = {
    filetype = "python",
    path = "src/pipeline/data_cleaner.py",
    lines = {
      "import logging",
      "from typing import List, Dict, Optional",
      "from datetime import datetime",
      "",
      "logger = logging.getLogger(__name__)",
      "",
      "",
      "class DataCleaner:",
      "    def __init__(self, config: Dict):",
      "        self.config = config",
      "        self.null_strategy = config.get('null_strategy', 'drop')",
      "        self.date_format = config.get('date_format', '%Y-%m-%d')",
      "",
      "    def clean(self, records: List[Dict]) -> List[Dict]:",
      "        cleaned = []",
      "        for record in records:",
      "            record = self._normalize_fields(record)",
      "            record = self._handle_nulls(record)",
      "            if record is not None:",
      "                cleaned.append(record)",
      "        logger.info(f'Cleaned {len(cleaned)}/{len(records)} records')",
      "        return cleaned",
      "",
      "    def _normalize_fields(self, record: Dict) -> Dict:",
      "        normalized = {}",
      "        for key, value in record.items():",
      "            normalized[key.strip().lower()] = value",
      "        return normalized",
      "",
      "    def _handle_nulls(self, record: Dict) -> Optional[Dict]:",
      "        if self.null_strategy == 'drop':",
      "            if any(v is None for v in record.values()):",
      "                return None",
      "        return record",
    },
  },
  tsx_component = {
    filetype = "typescriptreact",
    path = "src/components/UserForm.tsx",
    lines = {
      'import React, { useState, useCallback } from "react";',
      'import { useFormValidator } from "../hooks/useFormValidator";',
      "",
      "interface UserFormProps {",
      "  onSubmit: (data: FormData) => void;",
      "  initialData?: Partial<FormData>;",
      "}",
      "",
      "export const UserForm: React.FC<UserFormProps> = ({ onSubmit, initialData }) => {",
      '  const [email, setEmail] = useState(initialData?.email ?? "");',
      '  const [name, setName] = useState(initialData?.name ?? "");',
      "  const [errors, setErrors] = useState<Record<string, string>>({});",
      "",
      "  const validate = useFormValidator();",
      "",
      "  const handleSubmit = useCallback(",
      "    (e: React.FormEvent) => {",
      "      e.preventDefault();",
      "      const result = validate({ email, name });",
      "      if !result.valid) {",
      "        setErrors(result.errors);",
      "        return;",
      "      }",
      "      onSubmit({ email, name });",
      "    },",
      "    [email, name, validate, onSubmit]",
      "  );",
      "",
      "  return (",
      '    <form onSubmit={handleSubmit} className="space-y-4">',
      '      <input value={email} onChange={(e) => setEmail(e.target.value)} />',
      "    </form>",
      "  );",
      "};",
    },
  },
  nvim_config = {
    filetype = "lua",
    path = "lua/config/keymaps.lua",
    lines = {
      'local M = {}',
      'local utils = require("config.utils")',
      "",
      "M._keymaps = {",
      '  { "n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" } },',
      '  { "n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" } },',
      '  { "n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" } },',
      '  { "n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help tags" } },',
      '  { "n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle explorer" } },',
      "}",
      "",
      "function M.setup(opts)",
      "  for _, map in ipairs(M._keymaps) do",
      "    local mode, lhs, rhs, opts_inner = map[1], map[2], map[3], map[4]",
      '    vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", opts_inner, opts or {}))',
      "  end",
      "end",
      "",
      "return M",
    },
  },
  rust_structs = {
    filetype = "rust",
    path = "src/models/user.rs",
    lines = {
      "use serde::{Deserialize, Serialize};",
      "use chrono::{DateTime, Utc};",
      "",
      "#[derive(Debug, Clone, Serialize, Deserialize)]",
      "pub struct User {",
      "    pub id: i64,",
      "    pub username: String,",
      "    pub email: String,",
      "    pub created_at: DateTime<Utc>,",
      "    pub updated_at: DateTime<Utc>,",
      "}",
      "",
      "#[derive(Debug, Deserialize)]",
      "pub struct CreateUserRequest {",
      "    pub username: String,",
      "    pub email: String,",
      "    pub password: String,",
      "}",
      "",
      "impl User {",
      "    pub fn new(req: CreateUserRequest) -> Self {",
      "        let now = Utc::now();",
      "        Self {",
      "            id: 0,",
      "            username: req.username,",
      "            email: req.email,",
      "            created_at: now,",
      "            updated_at: now,",
      "        }",
      "    }",
      "}",
    },
  },
}

-- 用户自定义预设的存储表
local custom_presets = {}

-- 根据名称获取预设
function M.get(name)
  if name == "random" then
    -- [Lua概念] math.random(n) 返回 1 到 n 的随机整数。
    local names = M.list()
    local key = names[math.random(#names)]
    local src = builtins[key] or custom_presets[key]
    -- [Neovim API] vim.tbl_extend("force", t1, t2) 合并两个表。
    -- "force" 策略：t2 的值覆盖 t1 的同名键。
    -- 其他策略："keep"（不覆盖）、"error"（重复键报错）。
    return vim.tbl_extend("force", src, { name = key })
  end
  local src = builtins[name] or custom_presets[name]
  if not src then
    -- 未找到指定名称，使用第一个内置预设作为兜底
    local names = M.list()
    local fallback = names[1]
    src = builtins[fallback]
  end
  return vim.tbl_extend("force", src, { name = name })
end

-- 列出所有预设的名称
function M.list()
  local names = {}
  -- [Lua概念] pairs(t) 遍历所有键值对（包括非整数键），顺序不确定。
  -- 与 ipairs 不同：ipairs 只遍历整数索引 1,2,3,...，pairs 遍历所有键。
  -- [Lua概念] _ 是"占位变量"，Lua 惯用法：不需要用的值赋给 _（类似 Go 的 _）。
  for k, _ in pairs(builtins) do table.insert(names, k) end
  for k, _ in pairs(custom_presets) do table.insert(names, k) end
  return names
end

-- 添加用户自定义预设
function M.add(name, preset)
  custom_presets[name] = preset
end

return M
