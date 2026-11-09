-- Exact namespace summaries adapted from abhi-k9/nvim-config's diagnostic cache.
-- No diagnostic API or provider getter is replaced.
local M = {}
local attachment
local levels = { "error", "warning", "info", "hint", "other" }
local missing = {
  __index = function() return { count = 0 } end,
}

local function count_by_namespace(diagnostics)
  local buffers = {}
  for _, diagnostic in ipairs(diagnostics) do
    local groups = buffers[diagnostic.bufnr] or {}
    buffers[diagnostic.bufnr] = groups
    local summary = groups[diagnostic.namespace] or { count = 0, severity = 5, errors = {} }
    groups[diagnostic.namespace] = summary
    summary.count = summary.count + 1
    summary.severity = math.min(summary.severity, diagnostic.severity)
    local level = levels[diagnostic.severity] or "other"
    summary.errors[level] = (summary.errors[level] or 0) + 1
  end
  return buffers
end

function M.reset()
  if attachment then vim.api.nvim_del_augroup_by_id(attachment.group) end
  attachment = nil
end

local function attach()
  local counts, result
  local dirty = {}
  local group = vim.api.nvim_create_augroup("BufferlineDiagnosticCache", { clear = true })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(args)
      if counts then dirty[args.buf] = true end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      if counts then counts[args.buf] = nil end
      dirty[args.buf], result = nil, nil
    end,
  })

  local function get()
    if not counts then counts = count_by_namespace(vim.diagnostic.get()) end
    for bufnr in pairs(dirty) do
      counts[bufnr] = vim.api.nvim_buf_is_valid(bufnr) and count_by_namespace(vim.diagnostic.get(bufnr))[bufnr] or nil
      result = nil
    end
    dirty = {}
    -- Enable/disable does not emit DiagnosticChanged. Check once per group,
    -- rather than once per diagnostic, so every supported filter stays live.
    for bufnr, groups in pairs(counts) do
      for namespace, summary in pairs(groups) do
        local enabled = vim.diagnostic.is_enabled({ bufnr = bufnr, ns_id = namespace })
        if summary.enabled ~= enabled then result = nil end
        summary.enabled = enabled
      end
    end
    if not result then
      result = setmetatable({}, missing)
      for bufnr, groups in pairs(counts) do
        local summary = { count = 0, errors = {} }
        local severity = 5
        for _, item in pairs(groups) do
          if item.enabled then
            summary.count = summary.count + item.count
            severity = math.min(severity, item.severity)
            for level, count in pairs(item.errors) do
              summary.errors[level] = (summary.errors[level] or 0) + count
            end
          end
        end
        if summary.count > 0 then
          summary.level = levels[severity]
          result[bufnr] = summary
        end
      end
    end
    return result
  end

  attachment = { get = get, group = group }
end

function M.get()
  if not attachment then attach() end
  return attachment.get()
end

return M
