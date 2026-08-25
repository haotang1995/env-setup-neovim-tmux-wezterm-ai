-- Headless regression test for config.claude_proposals.
-- Run from the repository root:
--
-- nvim --headless -u NONE \
--   --cmd "set rtp^=/tmp/claudecode-nvim-2390c6e" \
--   --cmd "set rtp^=$PWD/nvim-config" \
--   -l nvim-config/tests/claude_proposals_test.lua

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function write(path, lines)
  local result = vim.fn.writefile(lines, path)
  assert_equal(result, 0, "write fixture")
end

local specs = dofile(vim.fn.getcwd() .. "/nvim-config/lua/plugins/ai.lua")
local claude_spec
for _, spec in ipairs(specs) do
  if spec[1] == "coder/claudecode.nvim" then
    claude_spec = spec
    break
  end
end
assert(claude_spec, "claudecode.nvim spec not found")
local opts = vim.deepcopy(claude_spec.opts)
opts.auto_start = false
require("claudecode").setup(opts)

local notifications = {}
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end

local policy = require("config.claude_proposals")
policy.setup()

local accepted = {}
package.loaded["claudecode.diff"] = {
  _resolve_diff_as_saved = function(tab_name, buffer)
    accepted[#accepted + 1] = { tab_name = tab_name, buffer = buffer }
  end,
}

local fixture = vim.fn.tempname() .. ".lua"
write(fixture, { "return 'base'" })
vim.cmd("edit " .. vim.fn.fnameescape(fixture))
local target_window = vim.api.nvim_get_current_win()
local target_buffer = vim.api.nvim_get_current_buf()

local bypass_count = 0

local function open_proposal(tab_name)
  local proposal_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(proposal_buffer, tab_name .. " (proposed)")
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = proposal_buffer })
  vim.api.nvim_buf_set_lines(proposal_buffer, 0, -1, false, { "return 'proposal'" })
  vim.b[proposal_buffer].claudecode_diff_tab_name = tab_name

  vim.api.nvim_set_current_win(target_window)
  vim.cmd("vsplit")
  local proposal_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(proposal_window, proposal_buffer)

  -- Simulate the plugin's unguarded accept handler. The policy must remove it.
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = proposal_buffer,
    callback = function()
      bypass_count = bypass_count + 1
      return true
    end,
  })

  policy._on_diff_opened({
    data = {
      tab_name = tab_name,
      file_path = fixture,
      new_file_path = fixture,
      is_new_file = false,
      diff_window = proposal_window,
      target_window = target_window,
    },
  })

  return proposal_window, proposal_buffer
end

local function close_proposal(tab_name, proposal_window, proposal_buffer)
  policy._on_diff_closed({
    data = {
      tab_name = tab_name,
      file_path = fixture,
      reason = "test cleanup",
    },
  })
  if vim.api.nvim_win_is_valid(proposal_window) then
    vim.api.nvim_win_close(proposal_window, true)
  end
  if vim.api.nvim_buf_is_valid(proposal_buffer) then
    vim.api.nvim_buf_delete(proposal_buffer, { force = true })
  end
end

-- Fresh proposal: :w must reach the guarded accept function, not the original
-- plugin BufWriteCmd.
policy._on_send_complete({ data = { file_path = fixture } })
local fresh_window, fresh_buffer = open_proposal("fresh")
assert_equal(policy._pending_count(), 1, "fresh proposal pending count")
vim.api.nvim_set_current_win(fresh_window)
vim.cmd("write")
assert_equal(#accepted, 1, "fresh proposal acceptance")
assert_equal(accepted[1].tab_name, "fresh", "accepted tab name")
assert_equal(bypass_count, 0, "unguarded BufWriteCmd removal")
close_proposal("fresh", fresh_window, fresh_buffer)
assert_equal(policy._pending_count(), 0, "fresh proposal close")

-- Disk changed after baseline: the public accept command must fail closed.
policy._on_send_complete({ data = { file_path = fixture } })
local disk_window, disk_buffer = open_proposal("stale-disk")
write(fixture, { "return 'external change'" })
vim.api.nvim_set_current_win(disk_window)
vim.cmd("ClaudeCodeDiffAccept")
assert_equal(#accepted, 1, "stale disk acceptance blocked")
close_proposal("stale-disk", disk_window, disk_buffer)

-- Restore the fixture and keep the target buffer coherent for the next case.
write(fixture, { "return 'base'" })
vim.api.nvim_buf_set_lines(target_buffer, 0, -1, false, { "return 'base'" })
vim.api.nvim_set_option_value("modified", false, { buf = target_buffer })

-- Original buffer changed after baseline: acceptance must fail closed.
policy._on_send_complete({ data = { file_path = fixture } })
local buffer_window, buffer_proposal = open_proposal("stale-buffer")
vim.api.nvim_buf_set_lines(target_buffer, 0, -1, false, { "return 'unsaved change'" })
vim.api.nvim_set_current_win(buffer_window)
vim.cmd("ClaudeCodeDiffAccept")
assert_equal(#accepted, 1, "stale buffer acceptance blocked")
close_proposal("stale-buffer", buffer_window, buffer_proposal)

-- A blocked :w must leave the guard armed. The plugin's own BufWriteCmd was
-- removed when the guard was installed, so a guard that deletes itself (any
-- Lua autocmd callback returning true does) leaves the proposal buffer with no
-- write handler at all: :w then fails E676 and the documented accept path is
-- dead for the rest of that proposal.
write(fixture, { "return 'base'" })
vim.api.nvim_buf_set_lines(target_buffer, 0, -1, false, { "return 'base'" })
vim.api.nvim_set_option_value("modified", false, { buf = target_buffer })
policy._on_send_complete({ data = { file_path = fixture } })
local retry_window, retry_buffer = open_proposal("retry")

local function guard_count(buffer)
  return #vim.api.nvim_get_autocmds({ event = "BufWriteCmd", buffer = buffer })
end
assert_equal(guard_count(retry_buffer), 1, "guard installed on the proposal buffer")

write(fixture, { "return 'external change'" })
vim.api.nvim_set_current_win(retry_window)
vim.cmd("write")
assert_equal(#accepted, 1, "stale :w blocked")
assert_equal(guard_count(retry_buffer), 1, "guard survives a blocked write")

local second_ok = pcall(vim.cmd, "write")
assert_equal(second_ok, true, "second :w still reaches the guard")
assert_equal(#accepted, 1, "second stale :w still blocked")

-- Restoring the source to its baseline must make the same buffer acceptable.
write(fixture, { "return 'base'" })
vim.cmd("write")
assert_equal(#accepted, 2, "refreshed :w accepts")
assert_equal(accepted[2].tab_name, "retry", "refreshed accept tab name")
close_proposal("retry", retry_window, retry_buffer)

-- Duplicate lifecycle events must not inflate or underflow the count.
vim.api.nvim_buf_set_lines(target_buffer, 0, -1, false, { "return 'base'" })
vim.api.nvim_set_option_value("modified", false, { buf = target_buffer })
policy._on_send_complete({ data = { file_path = fixture } })
local duplicate_window, duplicate_buffer = open_proposal("duplicate")
policy._on_diff_opened({
  data = {
    tab_name = "duplicate",
    file_path = fixture,
    diff_window = duplicate_window,
    target_window = target_window,
  },
})
assert_equal(policy._pending_count(), 1, "duplicate open is idempotent")
close_proposal("duplicate", duplicate_window, duplicate_buffer)
policy._on_diff_closed({ data = { tab_name = "duplicate", file_path = fixture } })
assert_equal(policy._pending_count(), 0, "duplicate close does not underflow")

-- A send that never produces a diff must not keep its baseline forever.
policy._state.sent_baselines = {}
local orphan = vim.fn.tempname() .. ".lua"
write(orphan, { "return 'orphan'" })
policy._on_send_complete({ data = { file_path = orphan } })
assert_equal(vim.tbl_count(policy._state.sent_baselines), 1, "orphan send baseline recorded")

local orphan_key = vim.fn.fnamemodify(orphan, ":p")
policy._state.sent_baselines[orphan_key].captured_at = os.time() - policy._sent_baseline_ttl_seconds - 1
policy._on_send_complete({ data = { file_path = fixture } })
assert_equal(policy._state.sent_baselines[orphan_key], nil, "expired send baseline pruned")
assert_equal(vim.tbl_count(policy._state.sent_baselines), 1, "live send baseline kept")

-- A baseline still inside the TTL survives an unrelated send.
policy._on_send_complete({ data = { file_path = orphan } })
assert_equal(vim.tbl_count(policy._state.sent_baselines), 2, "fresh send baselines kept")
vim.fn.delete(orphan)

vim.fn.delete(fixture)
print(("CLAUDE_PROPOSALS_TEST_OK notifications=%d"):format(#notifications))
