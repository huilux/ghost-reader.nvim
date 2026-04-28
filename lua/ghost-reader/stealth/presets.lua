local M = {}

function M.get(name)
  return {
    lines = {
      "package handler",
      "",
      'import "log"',
      'import "net/http"',
      "",
      "func HealthCheck(w http.ResponseWriter, r *http.Request) {",
      '  w.WriteHeader(http.StatusOK)',
      '  w.Write([]byte("ok"))',
      "}",
    },
    filetype = "go",
    path = "internal/handler/health.go",
  }
end

return M
