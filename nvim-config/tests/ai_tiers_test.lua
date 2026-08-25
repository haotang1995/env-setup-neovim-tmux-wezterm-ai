-- Headless regression test for the explicit in-editor AI tier routing.
-- Run from the repository root:
--
-- nvim --headless -u NONE -l nvim-config/tests/ai_tiers_test.lua

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function find_spec(specs, name)
  for _, spec in ipairs(specs) do
    if spec[1] == name then
      return spec
    end
  end
  error("plugin spec not found: " .. name)
end

local function find_key(spec, lhs)
  for _, key in ipairs(spec.keys or {}) do
    if key[1] == lhs then
      return key
    end
  end
  error(("key %s not found for %s"):format(lhs, spec[1]))
end

local specs = dofile(vim.fn.getcwd() .. "/nvim-config/lua/plugins/ai.lua")
assert_equal(#specs, 3, "AI plugin tier count")

local copilot = find_spec(specs, "zbirenbaum/copilot.lua")
assert_equal(copilot.opts.suggestion.keymap.accept, "<Tab>", "T0 FIM accept key")
assert_equal(copilot.opts.nes.keymap.accept_and_goto, "<Tab>", "T0 NES accept key")

local codecompanion = find_spec(specs, "olimorris/codecompanion.nvim")
assert_equal(codecompanion.version, "v19.22.0", "CodeCompanion pin")
assert_equal(codecompanion.opts.interactions.inline.adapter.name, "copilot", "T0.5 adapter")
-- Must stay an explicit id. "auto" strips the model from the request, which
-- drops the prompt cap to 12288 tokens and forces /chat/completions.
assert_equal(codecompanion.opts.interactions.inline.adapter.model, "gpt-5.6-luna", "T0.5 model")
local inline_key = find_key(codecompanion, "<leader>ai")
assert_equal(inline_key[2], ":CodeCompanion<CR>", "T0.5 trigger")
assert_equal(inline_key.mode, "x", "T0.5 visual-only scope")

local claude = find_spec(specs, "coder/claudecode.nvim")
assert_equal(find_key(claude, "<leader>as")[2], "<cmd>ClaudeCodeSend<CR>", "T1/T2 trigger")
assert_equal(claude.opts.focus_after_send, false, "Claude background focus policy")

print("AI_TIERS_TEST_OK")
