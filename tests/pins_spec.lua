local api = vim.api
local groups = require("bufferline.groups")
local key = "BufferlinePinnedBuffers"

describe("pin persistence", function()
  local buffers
  local function buffer(name, listed)
    local id = api.nvim_create_buf(listed ~= false, false)
    api.nvim_buf_set_name(id, name)
    buffers[#buffers + 1] = id
    return id
  end
  local function pinned(id) return groups._is_pinned({ id = id }) end
  local function restore(saved)
    vim.g[key] = saved
    api.nvim_exec_autocmds("SessionLoadPost", {})
  end
  before_each(function()
    buffers = {}
    groups.state.manual_groupings = {}
    vim.g[key] = nil
    groups.setup({ options = { groups = { items = { { name = "work" } } } } })
  end)
  after_each(function()
    for _, id in ipairs(buffers) do
      if api.nvim_buf_is_valid(id) then api.nvim_buf_delete(id, { force = true }) end
    end
    groups.state.manual_groupings = {}
    vim.g[key] = nil
  end)

  it("never treats a missing legacy filename as a pattern", function()
    local name = vim.fn.tempname()
    local wrong = buffer(name .. "-suffix")
    restore(name)
    assert.is_false(pinned(wrong))
  end)

  it("round-trips commas without pinning a filename fragment", function()
    local name = vim.fn.tempname()
    local wanted = buffer(name .. ",part.txt")
    local wrong = buffer(name)
    groups.add_element("pinned", { id = wanted })
    local saved = vim.g[key]
    groups.state.manual_groupings = {}
    restore(saved)
    assert.is_true(pinned(wanted))
    assert.is_false(pinned(wrong))
  end)

  it("replaces pins on every A to B to A restore and preserves other groups", function()
    local a, b, work = buffer(vim.fn.tempname()), buffer(vim.fn.tempname()), buffer(vim.fn.tempname())
    groups.add_element("work", { id = work })
    restore(api.nvim_buf_get_name(a))
    assert.is_true(pinned(a))
    restore(api.nvim_buf_get_name(b))
    assert.is_false(pinned(a))
    assert.is_true(pinned(b))
    restore(api.nvim_buf_get_name(a))
    assert.is_true(pinned(a))
    assert.is_false(pinned(b))
    assert.equals("work", groups.get_manual_group({ id = work }))
  end)

  it("does not duplicate its restore handler on repeated setup", function()
    local count = #api.nvim_get_autocmds({ event = "SessionLoadPost" })
    groups.setup({})
    assert.equals(count, #api.nvim_get_autocmds({ event = "SessionLoadPost" }))
  end)

  it("accepts an exact single legacy path, including pattern metacharacters", function()
    local id = buffer(vim.fn.tempname() .. " [x]*%.txt", false)
    restore(api.nvim_buf_get_name(id))
    assert.is_true(pinned(id))
    assert.is_false(vim.bo[id].buflisted)
  end)

  it("rejects ambiguous legacy CSV even when its fragments exist", function()
    local a, b = buffer(vim.fn.tempname()), buffer(vim.fn.tempname())
    restore(api.nvim_buf_get_name(a) .. "," .. api.nvim_buf_get_name(b))
    assert.is_false(pinned(a))
    assert.is_false(pinned(b))
  end)

  it("validates the entire payload before assigning any pins", function()
    local id = buffer(vim.fn.tempname())
    for _, value in ipairs({
      42,
      {},
      "bufferline-pins-v2:[]",
      "bufferline-pins-v1:{broken",
      "bufferline-pins-v1:" .. vim.json.encode({ api.nvim_buf_get_name(id), false }),
      'bufferline-pins-v1:["bad\\u0000name"]',
      'bufferline-pins-v1:[""]',
      'bufferline-pins-v1:{"name":"file"}',
    }) do
      groups.add_element("pinned", { id = id })
      restore(value)
      assert.is_false(pinned(id))
    end
  end)

  it("skips missing buffers and duplicates without creating or listing buffers", function()
    local id = buffer(vim.fn.tempname(), false)
    local before = api.nvim_list_bufs()
    restore("bufferline-pins-v1:" .. vim.json.encode({
      api.nvim_buf_get_name(id),
      vim.fn.tempname(),
      api.nvim_buf_get_name(id),
    }))
    assert.is_true(pinned(id))
    assert.same(before, api.nvim_list_bufs())
    assert.is_false(vim.bo[id].buflisted)
  end)

  it("clears stale pins for empty or absent metadata", function()
    local id = buffer(vim.fn.tempname())
    for _, value in ipairs({ "", "bufferline-pins-v1:[]" }) do
      groups.add_element("pinned", { id = id })
      restore(value)
      assert.is_false(pinned(id))
    end
    groups.add_element("pinned", { id = id })
    restore(nil)
    assert.is_false(pinned(id))
  end)

  it("handles wiped, renamed and unnamed pins without invalid buffer errors", function()
    local id = buffer(vim.fn.tempname())
    groups.add_element("pinned", { id = id })
    api.nvim_buf_set_name(id, vim.fn.tempname() .. ",renamed")
    local saved = vim.g[key]
    groups.state.manual_groupings = {}
    restore(saved)
    assert.is_true(pinned(id))
    api.nvim_buf_delete(id, { force = true })
    assert.is_false(pinned(id))
    groups.state.manual_groupings[id] = "pinned" -- stale IDs from old state
    local unnamed = api.nvim_create_buf(true, false)
    buffers[#buffers + 1] = unnamed
    groups.add_element("pinned", { id = unnamed })
    assert.equals("bufferline-pins-v1:[]", vim.g[key])
  end)

  it("round-trips native session files and clears globals absent from session B", function()
    local id = buffer(vim.fn.tempname() .. ',[x] "é.txt')
    local session_a, session_b = vim.fn.tempname(), vim.fn.tempname()
    local options = vim.o.sessionoptions
    vim.o.sessionoptions = "buffers,globals"
    groups.add_element("pinned", { id = id })
    vim.cmd.mksession({ session_a, bang = true })
    vim.g[key] = nil
    vim.cmd.mksession({ session_b, bang = true })
    local ok, err = pcall(function()
      for _, path in ipairs({ session_a, session_b, session_a }) do
        vim.cmd.source(path)
        assert.equals(path == session_a, pinned(id))
      end
    end)
    vim.o.sessionoptions = options
    vim.fn.delete(session_a)
    vim.fn.delete(session_b)
    assert.is_true(ok, tostring(err))
  end)
end)
