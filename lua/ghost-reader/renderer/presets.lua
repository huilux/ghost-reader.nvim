local M = {}

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
      "    end",
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

local custom_presets = {}

function M.get(name)
  if name == "random" then
    local names = M.list()
    local key = names[math.random(#names)]
    local src = builtins[key] or custom_presets[key]
    return vim.tbl_extend("force", src, { name = key })
  end
  local src = builtins[name] or custom_presets[name]
  if not src then
    local names = M.list()
    local fallback = names[1]
    src = builtins[fallback]
  end
  return vim.tbl_extend("force", src, { name = name })
end

function M.list()
  local names = {}
  for k, _ in pairs(builtins) do
    table.insert(names, k)
  end
  for k, _ in pairs(custom_presets) do
    table.insert(names, k)
  end
  return names
end

function M.add(name, preset)
  custom_presets[name] = preset
end

return M
