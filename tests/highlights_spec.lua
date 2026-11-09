---@diagnostic disable: need-check-nil
describe("Highlights -", function()
  local highlights ---@module "bufferline.highlights"
  local config ---@module "bufferline.config"

  before_each(function()
    package.loaded["bufferline.highlights"] = nil
    package.loaded["bufferline.config"] = nil

    highlights = require("bufferline.highlights")
    config = require("bufferline.config")
  end)

  it("should set highlights as default", function()
    config.setup({ options = { themable = true } })
    config.apply()
    local hl = highlights.set("BufferLineBufferSelected", { bold = true })
    assert.truthy(hl)
    assert.is_true(hl.default)
  end)

  it("should not set highlights as default if themable = false", function()
    config.setup({ options = { themable = false } })
    config.apply()
    local hl = highlights.set("BufferLineBufferSelected", { bold = true })
    assert.truthy(hl)
    assert.is_false(hl.default)
  end)

  it("preserves explicit false and prefers vim.nonnil without deprecation calls", function()
    config.setup({ options = { themable = true } })
    config.apply()
    local fallback, nonnil = vim.F.if_nil, vim.nonnil
    local called = false
    vim.nonnil = function(value, default)
      called = true
      if value ~= nil then return value end
      return default
    end
    vim.F.if_nil = function() error("deprecated fallback used") end
    package.loaded["bufferline.highlights"] = nil
    local ok, err = pcall(function()
      local hl = require("bufferline.highlights").set("BufferLineCompatibilityTest", { bold = true, default = false })
      assert.is_false(hl.default)
    end)
    vim.F.if_nil, vim.nonnil = fallback, nonnil
    package.loaded["bufferline.highlights"] = nil
    assert.is_true(ok, tostring(err))
    assert.is_true(called)
  end)
end)
