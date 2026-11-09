-- Opt-in attached-UI integration probe. No downloads or private config loading.
local api = vim.api
local config_root = assert(vim.env.BUFFERLINE_CONFIG_ROOT)
for _, path in ipairs({
  config_root,
  assert(vim.env.BUFFERLINE_ROOT),
  assert(vim.env.BUFFERLINE_SCOPE),
  assert(vim.env.BUFFERLINE_THEME),
  assert(vim.env.BUFFERLINE_ICONS),
}) do
  vim.opt.rtp:append(path)
end
assert(#api.nvim_list_uis() > 0, "an attached Neovim UI is required")
vim.g.config_local_file = false
vim.o.swapfile, vim.o.hidden, vim.o.confirm, vim.o.mouse = false, true, false, "a"
vim.o.termguicolors = true
local settings = require("config.settings")
local phase = arg[1]
local scoped = phase ~= "global"
settings.configure({ ui = { icons = true }, sessions = { global_buffers = not scoped } })
if scoped then require("scope").setup({}) end
require("nvim-web-devicons").setup({})
require("catppuccin").setup({})
vim.cmd.colorscheme("catppuccin-mocha")
local spec
for _, item in ipairs(dofile(config_root .. "/lua/plugins/ui.lua")) do
  if item[1] == "akinsho/bufferline.nvim" or item[1] == "abhi-k9/bufferline.nvim" then spec = item end
end
local line, groups = require("bufferline"), require("bufferline.groups")
local opts = spec.opts()
opts.options.diagnostics_cache = true
line.setup(opts)
local function draw()
  vim.cmd.redraw()
  return _G.nvim_bufferline()
end
local function names()
  draw()
  local result = {}
  for _, element in ipairs(line.get_elements().elements) do
    result[#result + 1] = api.nvim_buf_get_name(element.id)
  end
  return result
end
local function new(name)
  local id = vim.fn.bufadd(vim.env.BUFFERLINE_PROBE_DIR .. "/" .. name)
  vim.fn.bufload(id)
  vim.bo[id].buflisted = true
  return id
end
local function pin(id) groups.add_element("pinned", { id = id }) end
local function find(name)
  for _, id in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(id) == vim.env.BUFFERLINE_PROBE_DIR .. "/" .. name then return id end
  end
end

if phase == "save" then
  local a, hidden = new("alpha.lua"), new("hidden,pin.lua")
  api.nvim_set_current_buf(a)
  pin(hidden)
  vim.cmd.tabnew()
  local b = new("beta.lua")
  api.nvim_set_current_buf(b)
  require("config.session").save_scopes()
  vim.o.sessionoptions = "buffers,globals,tabpages,winsize"
  vim.cmd.mksession({ vim.env.BUFFERLINE_PROBE_DIR .. "/session.vim", bang = true })
  groups.remove_element("pinned", { id = hidden })
  pin(b)
  vim.cmd.mksession({ vim.env.BUFFERLINE_PROBE_DIR .. "/session-b.vim", bang = true })
  return { phase = phase, pins = vim.g.BufferlinePinnedBuffers }
elseif phase == "restore" then
  local hidden
  for _, filename in ipairs({ "session.vim", "session-b.vim", "session.vim" }) do
    vim.cmd.source(vim.env.BUFFERLINE_PROBE_DIR .. "/" .. filename)
    for _, hook in ipairs(dofile(config_root .. "/lua/plugins/session.lua").opts.post_restore_cmds) do
      hook()
    end
    hidden = assert(find("hidden,pin.lua"), "scope did not recreate the hidden buffer")
    assert(line.is_pinned(hidden) == (filename == "session.vim"), "hidden scope pin did not follow session")
    assert(
      line.is_pinned(assert(find("beta.lua"))) == (filename == "session-b.vim"),
      "stale pin survived session switch"
    )
  end
  assert(not vim.bo[hidden].buflisted, "hidden scope buffer became listed")
  api.nvim_set_current_tabpage(api.nvim_list_tabpages()[1])
  assert(names()[1]:find("hidden,pin.lua", 1, true), "hidden pin did not sort first")
  return { phase = phase, visible = names(), pinned = line.is_pinned(hidden) }
end

local initial = api.nvim_get_current_buf()
local a, b, c = new("alpha.lua"), new("beta.lua"), new("gamma.lua")
api.nvim_set_current_buf(a)
if api.nvim_buf_get_name(initial) == "" then api.nvim_buf_delete(initial, { force = true }) end
pin(c)
assert(names()[1] == api.nvim_buf_get_name(c), "pin is not first")
line.go_to(1)
assert(api.nvim_get_current_buf() == c, "numeric navigation ignored visual order")
line.cycle(1)
assert(api.nvim_get_current_buf() == a, "cycle ignored visual order")
line.go_to(-1)
assert(api.nvim_get_current_buf() == b, "last navigation changed")
line.move(-1)
assert(names()[2] == api.nvim_buf_get_name(b), "manual ordering changed")
local letter
for _, item in ipairs(require("bufferline.state").components) do
  if item.id == a then letter = item.letter end
end
api.nvim_feedkeys(letter, "t", false)
line.pick()
assert(api.nvim_get_current_buf() == a, "letter pick failed")

local ns = api.nvim_create_namespace("fork-ui-probe")
local diagnostics = {}
for severity = 1, 4 do
  diagnostics[#diagnostics + 1] = { lnum = 0, col = 0, severity = severity, message = "probe" }
end
vim.diagnostic.config({ virtual_text = false, signs = false, underline = false })
vim.diagnostic.set(ns, a, diagnostics)
draw()
local summary
for _, item in ipairs(require("bufferline.state").components) do
  if item.id == a then summary = item.diagnostics end
end
assert(vim.deep_equal(summary.errors, { error = 1, warning = 1, info = 1, hint = 1 }))

-- Keyboard menu and the shared safe deletion callback must preserve dirty text.
api.nvim_buf_set_lines(a, 0, -1, false, { "keep these unsaved edits" })
require("config.util").buffer_menu()
assert(api.nvim_win_get_config(0).relative == "editor", "keyboard menu did not open")
local dismiss = vim.fn.maparg("q", "n", false, true).callback
assert(type(dismiss) == "function")
dismiss()
opts.options.close_command(a)
assert(api.nvim_buf_is_valid(a) and vim.bo[a].modified, "close discarded edits")

-- Probe a real tabline mouse event through Neovim's UI input API.
draw()
local row = ""
for col = 1, vim.o.columns do
  row = row .. vim.fn.screenstring(1, col)
end
local mouse_col
for col = 1, vim.o.columns - 4 do
  local text = ""
  for n = 0, 4 do
    text = text .. vim.fn.screenstring(1, col + n)
  end
  if text == "alpha" then
    mouse_col = col - 1
    break
  end
end
assert(mouse_col, "alpha is absent from the rendered tabline: " .. row)
function _G.finish_bufferline_ui_probe()
  assert(api.nvim_win_get_config(0).relative == "editor", "mouse menu did not open")
  vim.fn.maparg("q", "n", false, true).callback()

  -- Model Neo-tree's filetype/window boundary with the real configured offset.
  vim.cmd("topleft vnew")
  local panel = api.nvim_get_current_win()
  vim.bo.filetype = "neo-tree"
  api.nvim_win_set_width(panel, 24)
  draw()
  assert(require("bufferline.state").left_offset_size >= 24, "Neo-tree offset missing")
  api.nvim_win_close(panel, true)

  local themes = {}
  for _, flavour in ipairs({ "latte", "frappe", "macchiato", "mocha" }) do
    vim.cmd.colorscheme("catppuccin-" .. flavour)
    local text = draw()
    assert(#text > 0)
    themes[#themes + 1] = flavour
  end
  settings.configure({ ui = { icons = false } })
  package.loaded["config.icons"] = nil
  for _, item in ipairs(dofile(config_root .. "/lua/plugins/ui.lua")) do
    if item[1] == "akinsho/bufferline.nvim" or item[1] == "abhi-k9/bufferline.nvim" then spec = item end
  end
  opts = spec.opts()
  opts.options.diagnostics_cache = true
  line.setup(opts)
  assert(opts.options.show_buffer_icons == false)
  assert(opts.options.diagnostics_indicator(nil, nil, summary.errors) == "E 1 W 1 I 1 H 1")
  draw()

  local first_tab = api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  local other = new("other-tab.lua")
  api.nvim_set_current_buf(other)
  local other_names = names()
  if scoped then
    assert(#other_names == 2 or #other_names == 1, "other tab contains unrelated buffers")
    assert(not vim.bo[c].buflisted and line.is_pinned(c), "scope lost the hidden pin")
  else
    assert(vim.bo[c].buflisted and #other_names >= 4, "global mode hid buffers")
  end
  api.nvim_set_current_tabpage(first_tab)
  assert(names()[1] == api.nvim_buf_get_name(c))
  draw()
  assert(vim.o.columns == 48 and #names() >= 3, "narrow render lost navigation state")
  return {
    phase = phase,
    themes = themes,
    visible = names(),
    diagnostics = summary,
    mouse_menu = true,
    keyboard_menu = true,
    dirty_preserved = true,
  }
end
return { mouse_probe = true, column = mouse_col }
