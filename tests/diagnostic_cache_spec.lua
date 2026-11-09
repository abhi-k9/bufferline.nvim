-- Adapted from abhi-k9/nvim-config tests/bufferline_diagnostics_spec.lua.
local api = vim.api
local options = { diagnostics = "nvim_lsp", diagnostics_cache = true }

describe("cached Bufferline diagnostic counts", function()
  local diagnostics, buffers, namespaces, config, get, mode, reads, native_getter

  local function publish(namespace, bufnr, severities)
    local items = {}
    for _, severity in ipairs(severities) do
      items[#items + 1] = { lnum = 0, col = 0, message = "diagnostic", severity = severity }
    end
    vim.diagnostic.set(namespace, bufnr, items)
  end

  before_each(function()
    config = vim.diagnostic.config()
    vim.diagnostic.enable(true)
    vim.diagnostic.config({
      virtual_text = false,
      signs = false,
      underline = false,
      update_in_insert = false,
    })
    buffers = { api.nvim_create_buf(true, false), api.nvim_create_buf(true, false) }
    namespaces = {
      api.nvim_create_namespace("bufferline-test-a"),
      api.nvim_create_namespace("bufferline-test-b"),
    }
    diagnostics = require("bufferline.diagnostics")
    diagnostics.setup()
    native_getter = diagnostics.get
    get, mode, reads = vim.diagnostic.get, api.nvim_get_mode, {}
    vim.diagnostic.get = function(bufnr, ...)
      reads[#reads + 1] = bufnr or false
      return get(bufnr, ...)
    end
  end)

  after_each(function()
    vim.diagnostic.get, api.nvim_get_mode = get, mode
    diagnostics.setup()
    diagnostics.get = native_getter
    vim.diagnostic.enable(true)
    for _, namespace in ipairs(namespaces) do
      vim.diagnostic.enable(true, { ns_id = namespace })
      vim.diagnostic.reset(namespace)
    end
    for _, bufnr in ipairs(buffers) do
      if api.nvim_buf_is_valid(bufnr) then api.nvim_buf_delete(bufnr, { force = true }) end
    end
    vim.diagnostic.config(config)
  end)

  it("seeds existing diagnostics and reuses counts on unchanged redraws", function()
    publish(namespaces[1], buffers[1], { 1, 2, 2 })
    publish(namespaces[2], buffers[1], { 3, 4 })
    local result = diagnostics.get(options)
    assert.same(
      { count = 5, level = "error", errors = { error = 1, warning = 2, info = 1, hint = 1 } },
      result[buffers[1]]
    )
    assert.same({ false }, reads)
    for _ = 1, 100 do
      assert.equals(result, diagnostics.get(options))
    end
    assert.equals(1, #reads)
    assert.equals(0, result[buffers[2]].count)
  end)

  it("coalesces changes and refreshes only the affected buffer across namespaces", function()
    publish(namespaces[1], buffers[1], { 1 })
    publish(namespaces[2], buffers[1], { 2 })
    publish(namespaces[1], buffers[2], { 3 })
    diagnostics.get(options)
    publish(namespaces[1], buffers[1], { 4 })
    publish(namespaces[1], buffers[1], { 3, 4 })
    local result = diagnostics.get(options)
    assert.same({ false, buffers[1] }, reads)
    assert.same({ count = 3, level = "warning", errors = { warning = 1, info = 1, hint = 1 } }, result[buffers[1]])
    assert.equals(1, result[buffers[2]].count)
    vim.diagnostic.reset(namespaces[2], buffers[1])
    assert.equals("info", diagnostics.get(options)[buffers[1]].level)
    vim.diagnostic.reset(nil, buffers[1])
    assert.equals(0, diagnostics.get(options)[buffers[1]].count)
  end)

  it("observes all enable filters without diagnostic events or rescanning items", function()
    publish(namespaces[1], buffers[1], { 1 })
    publish(namespaces[2], buffers[1], { 2 })
    publish(namespaces[1], buffers[2], { 3 })
    diagnostics.get(options)
    vim.diagnostic.enable(false, { ns_id = namespaces[1] })
    assert.equals("warning", diagnostics.get(options)[buffers[1]].level)
    assert.equals(0, diagnostics.get(options)[buffers[2]].count)
    vim.diagnostic.enable(true, { ns_id = namespaces[1] })
    vim.diagnostic.enable(false, { bufnr = buffers[1], ns_id = namespaces[1] })
    assert.equals(1, diagnostics.get(options)[buffers[1]].count)
    vim.diagnostic.enable(true, { bufnr = buffers[1], ns_id = namespaces[1] })
    assert.equals(2, diagnostics.get(options)[buffers[1]].count)
    vim.diagnostic.enable(false, { bufnr = buffers[1] })
    assert.equals(0, diagnostics.get(options)[buffers[1]].count)
    assert.equals(1, diagnostics.get(options)[buffers[2]].count)
    vim.diagnostic.enable(true, { bufnr = buffers[1] })
    assert.equals(2, diagnostics.get(options)[buffers[1]].count)
    vim.diagnostic.enable(false)
    assert.equals(0, diagnostics.get(options)[buffers[1]].count)
    vim.diagnostic.enable(true)
    assert.equals(2, diagnostics.get(options)[buffers[1]].count)
    assert.same({ false }, reads)
  end)

  it("freezes insert/replace counts until normal mode when updates are disabled", function()
    publish(namespaces[1], buffers[1], { 1 })
    local old = diagnostics.get(options)
    publish(namespaces[1], buffers[1], { 2, 3 })
    for _, insert_mode in ipairs({ "i", "ic", "ix", "R", "Rc", "Rx" }) do
      api.nvim_get_mode = function() return { mode = insert_mode } end
      assert.equals(old, diagnostics.get(options))
    end
    assert.same({ false }, reads)
    api.nvim_get_mode = mode
    local result = diagnostics.get(options)
    assert.equals(2, result[buffers[1]].count)
    assert.equals("warning", result[buffers[1]].level)
    assert.same({ false, buffers[1] }, reads)
  end)

  it("refreshes during insert mode when Neovim requests it", function()
    publish(namespaces[1], buffers[1], { 1 })
    diagnostics.get(options)
    vim.diagnostic.config({ update_in_insert = true })
    api.nvim_get_mode = function() return { mode = "i" } end
    publish(namespaces[1], buffers[1], { 4 })
    assert.equals("hint", diagnostics.get(options)[buffers[1]].level)
    assert.same({ false, buffers[1] }, reads)
  end)

  it("removes wiped buffers even if they have pending updates", function()
    publish(namespaces[1], buffers[1], { 1 })
    publish(namespaces[2], buffers[2], { 2 })
    diagnostics.get(options)
    publish(namespaces[1], buffers[1], { 3 })
    api.nvim_buf_delete(buffers[1], { force = true })
    local result = diagnostics.get(options)
    assert.is_nil(rawget(result, buffers[1]))
    assert.equals(1, result[buffers[2]].count)
    assert.same({ false }, reads)
  end)

  it("receives new diagnostics after initially caching an empty workspace", function()
    assert.equals(0, diagnostics.get(options)[buffers[1]].count)
    publish(namespaces[1], buffers[1], { 2 })
    assert.equals(1, diagnostics.get(options)[buffers[1]].count)
    assert.same({ false, buffers[1] }, reads)
  end)

  it("does no diagnostic work when indicators are disabled", function()
    publish(namespaces[1], buffers[1], { 1 })
    assert.equals(0, diagnostics.get({ diagnostics = false })[buffers[1]].count)
    assert.equals(0, #reads)
    assert.equals(1, diagnostics.get(options)[buffers[1]].count)
  end)

  it("checks enable state per namespace group rather than per diagnostic", function()
    local items = {}
    for _ = 1, 2000 do
      items[#items + 1] = 1
    end
    publish(namespaces[1], buffers[1], items)
    assert.equals(2000, diagnostics.get(options)[buffers[1]].count)
    local enabled, calls = vim.diagnostic.is_enabled, 0
    vim.diagnostic.is_enabled = function(...)
      calls = calls + 1
      return enabled(...)
    end
    local ok, result = pcall(function()
      for _ = 1, 10 do
        diagnostics.get(options)
      end
    end)
    vim.diagnostic.is_enabled = enabled
    assert.is_true(ok, result)
    assert.equals(10, calls)
    assert.same({ false }, reads)
  end)

  it("preserves the CoC diagnostic provider", function()
    local action, initialized = vim.fn.CocActionAsync, vim.g.coc_service_initialized
    api.nvim_buf_set_name(buffers[1], vim.fn.tempname())
    vim.g.coc_service_initialized = 1
    vim.fn.CocActionAsync = function(_, callback)
      callback(vim.NIL, { { file = api.nvim_buf_get_name(buffers[1]), level = 2 } })
    end
    local ok, result = pcall(function()
      diagnostics.refresh_coc_diagnostics()
      return diagnostics.get({ diagnostics = "coc" })
    end)
    vim.fn.CocActionAsync, vim.g.coc_service_initialized = action, initialized
    assert.is_true(ok, result)
    assert.same({ count = 1, level = "warning", errors = { warning = 1 } }, result[buffers[1]])
    assert.equals(0, #reads)
  end)

  it("keeps rendered buffer indicators current across changes and toggles", function()
    local bufferline = require("bufferline")
    bufferline.setup({
      options = { diagnostics = "nvim_lsp", diagnostics_update_on_event = true, diagnostics_cache = true },
    })
    local function rendered()
      _G.nvim_bufferline()
      for _, component in ipairs(require("bufferline.state").components) do
        if component.id == buffers[1] then return component.diagnostics end
      end
      error("buffer not rendered")
    end
    publish(namespaces[1], buffers[1], { 1, 1 })
    publish(namespaces[2], buffers[1], { 2 })
    assert.equals(3, rendered().count)
    publish(namespaces[1], buffers[1], { 3 })
    assert.equals(2, rendered().count)
    assert.equals("warning", rendered().level)
    vim.diagnostic.enable(false, { ns_id = namespaces[2] })
    assert.equals("info", rendered().level)
    vim.diagnostic.enable(true, { ns_id = namespaces[2] })
    assert.equals(2, rendered().count)
    vim.diagnostic.handlers.bufferline = nil
  end)

  it("resets ownership on repeated setup and supports disabling the cache", function()
    local bufferline = require("bufferline")
    local getter = diagnostics.get
    for _ = 1, 2 do
      bufferline.setup({ options = options })
      publish(namespaces[1], buffers[1], { 1, 2, 3, 4 })
      assert.equals(4, diagnostics.get(options)[buffers[1]].count)
      assert.equals(2, #api.nvim_get_autocmds({ group = "BufferlineDiagnosticCache" }))
    end
    assert.equals(getter, diagnostics.get)
    bufferline.setup({ options = { diagnostics = "nvim_lsp" } })
    assert.equals(0, vim.fn.exists("#BufferlineDiagnosticCache"))
    reads = {}
    for _ = 1, 2 do
      assert.equals(4, diagnostics.get({ diagnostics = "nvim_lsp" })[buffers[1]].count)
    end
    assert.same({ false, false }, reads)
    bufferline.setup({ options = options })
    assert.equals(4, diagnostics.get(options)[buffers[1]].count)
  end)

  it("does not mix frozen results when switching diagnostic providers", function()
    publish(namespaces[1], buffers[1], { 1 })
    diagnostics.get(options)
    vim.g.coc_service_initialized = 1
    api.nvim_get_mode = function() return { mode = "i" } end
    assert.equals(0, diagnostics.get({ diagnostics = "coc", diagnostics_update_in_insert = false })[buffers[1]].count)
    assert.equals(1, diagnostics.get(options)[buffers[1]].count)
    vim.g.coc_service_initialized = nil
  end)
end)
