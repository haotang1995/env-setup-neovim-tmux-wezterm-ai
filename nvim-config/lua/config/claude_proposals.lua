-- Policy and tmux UI around claudecode.nvim proposals.
--
-- claudecode.nvim supplies the IDE connection and diff. This module adds:
--   * idempotent pending-proposal accounting;
--   * a non-focusing tmux window marker and notification;
--   * proposal-buffer-local gda/gdr controls;
--   * a hash guard for the plugin's documented accept paths.
--
-- The accept wrapper uses claudecode.diff._resolve_diff_as_saved from the
-- pinned plugin commit. That is deliberate and must be revalidated on upgrades.
-- It does not sandbox Claude shell commands; write-capable tools must not be
-- auto-approved until the V0 bypass tests pass.

local M = {}

local uv = vim.uv or vim.loop
local group_name = "ClaudeProposalPolicy"

local state = {
  pending = {},
  baselines = {},
  sent_baselines = {},
  tmux_window_id = nil,
  setup_done = false,
}

-- A send baseline is consumed when a diff opens for the same path. A send that
-- never produces one (Claude answers in chat, or edits a different file) would
-- otherwise leave its entry behind for the life of the session, so entries
-- older than this are dropped on the next capture. A send whose diff arrives
-- after the TTL falls back to the diff-open baseline, which is the same
-- behaviour as a proposal that was never preceded by a send.
local sent_baseline_ttl_seconds = 30 * 60

local function table_count(values)
  local count = 0
  for _ in pairs(values) do
    count = count + 1
  end
  return count
end

local function trim(value)
  return (value or ""):gsub("%s+$", "")
end

local function normalize_path(path)
  if not path or path == "" then
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
end

local function tmux_command(args)
  if not vim.env.TMUX or not vim.env.TMUX_PANE or vim.fn.executable("tmux") ~= 1 then
    return nil
  end

  local command = { "tmux" }
  vim.list_extend(command, args)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return trim(output)
end

local function tmux_window_id()
  if state.tmux_window_id then
    return state.tmux_window_id
  end

  local id = tmux_command({
    "display-message",
    "-p",
    "-t",
    vim.env.TMUX_PANE,
    "#{window_id}",
  })
  if id and id ~= "" then
    state.tmux_window_id = id
  end
  return state.tmux_window_id
end

local function update_tmux_marker()
  local id = tmux_window_id()
  if not id then
    return
  end

  local count = table_count(state.pending)
  tmux_command({
    "set-option",
    "-w",
    "-t",
    id,
    "@ai_proposal_count",
    tostring(count),
  })
  tmux_command({
    "set-option",
    "-w",
    "-t",
    id,
    "@ai_proposal_marker",
    count > 0 and " 🤖" or "",
  })
end

local function disk_snapshot(path)
  path = normalize_path(path)
  if not path then
    return { exists = false, hash = nil }
  end

  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return { exists = false, hash = nil }
  end

  local stat = uv.fs_fstat(fd)
  local contents = stat and uv.fs_read(fd, stat.size, 0) or nil
  uv.fs_close(fd)
  if contents == nil then
    return { exists = false, hash = nil }
  end

  return {
    exists = true,
    hash = vim.fn.sha256(contents),
  }
end

local function buffer_hash(buffer)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local contents = table.concat(lines, "\n")
  if #lines > 0 and vim.api.nvim_get_option_value("endofline", { buf = buffer }) then
    contents = contents .. "\n"
  end
  return vim.fn.sha256(contents)
end

local function find_loaded_buffer(path)
  path = normalize_path(path)
  if not path then
    return nil
  end

  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_is_loaded(buffer) then
      local name = normalize_path(vim.api.nvim_buf_get_name(buffer))
      if name == path then
        return buffer
      end
    end
  end
  return nil
end

local function capture_baseline(path, target_buffer, source)
  path = normalize_path(path)
  target_buffer = target_buffer or find_loaded_buffer(path)
  return {
    path = path,
    disk = disk_snapshot(path),
    target_buffer = target_buffer,
    target_hash = buffer_hash(target_buffer),
    source = source,
  }
end

local function proposal_key(data)
  if data and data.tab_name and data.tab_name ~= "" then
    return data.tab_name
  end
  return normalize_path(data and data.file_path) or "unknown-proposal"
end

local function same_snapshot(before, after)
  return before.exists == after.exists and before.hash == after.hash
end

local function freshness(tab_name)
  local baseline = state.baselines[tab_name]
  if not baseline then
    return false, "proposal has no recorded source baseline"
  end

  local current_disk = disk_snapshot(baseline.path)
  if not same_snapshot(baseline.disk, current_disk) then
    return false, "the on-disk target changed after the proposal baseline"
  end

  if baseline.target_hash ~= nil then
    if not baseline.target_buffer or not vim.api.nvim_buf_is_valid(baseline.target_buffer) then
      return false, "the original target buffer is no longer available"
    end
    if buffer_hash(baseline.target_buffer) ~= baseline.target_hash then
      return false, "the original target buffer changed after the proposal baseline"
    end
  end

  return true
end

local function stale_notification(reason)
  vim.notify(
    "Claude proposal is stale: "
      .. reason
      .. ".\nThe proposal was not accepted; regenerate it or reject it.",
    vim.log.levels.ERROR,
    { title = "Claude proposal blocked" }
  )
end

local function accept(tab_name, proposal_buffer)
  local fresh, reason = freshness(tab_name)
  if not fresh then
    stale_notification(reason)
    return false
  end

  local ok, diff = pcall(require, "claudecode.diff")
  if not ok or type(diff._resolve_diff_as_saved) ~= "function" then
    vim.notify(
      "Pinned Claude diff accept API is unavailable; proposal left untouched.",
      vim.log.levels.ERROR,
      { title = "Claude proposal blocked" }
    )
    return false
  end

  diff._resolve_diff_as_saved(tab_name, proposal_buffer)
  return true
end

local function install_accept_guard(proposal_buffer, tab_name, group)
  -- This is a plugin-owned acwrite scratch buffer. Remove its existing
  -- BufWriteCmd handler so :w cannot accept before our freshness check.
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({
    event = "BufWriteCmd",
    buffer = proposal_buffer,
  })) do
    pcall(vim.api.nvim_del_autocmd, autocmd.id)
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = proposal_buffer,
    desc = "Accept a Claude proposal only when its source is fresh",
    callback = function()
      if accept(tab_name, proposal_buffer) then
        pcall(vim.cmd, "diffoff")
      end
      -- The proposal travels back through MCP; never write the scratch buffer.
      -- Return nothing. A Lua autocmd callback that returns true is DELETED by
      -- Neovim, which would drop this guard after the first blocked write and
      -- leave the buffer with no BufWriteCmd at all (:w then fails E676). The
      -- plugin's own handler can return true because it always resolves the
      -- diff; this one has to survive declining. buftype=acwrite has no default
      -- write to suppress, so doing nothing here is already "don't write".
    end,
  })
end

local function install_diff_mappings(proposal_buffer)
  vim.keymap.set("n", "gda", function()
    M.accept_current()
  end, {
    buffer = proposal_buffer,
    desc = "Accept Claude proposal",
    silent = true,
  })

  vim.keymap.set("n", "gdr", "<cmd>ClaudeCodeDiffDeny<CR>", {
    buffer = proposal_buffer,
    desc = "Reject Claude proposal",
    silent = true,
  })
end

local function notify_proposal(data)
  local path = normalize_path(data.file_path) or data.file_path or "unknown file"
  local filename = vim.fn.fnamemodify(path, ":t")
  local window_name = tmux_command({
    "display-message",
    "-p",
    "-t",
    vim.env.TMUX_PANE,
    "#{window_name}",
  })
  local location = window_name and window_name ~= "" and window_name or "this Neovim"
  local message = ("AI proposal ready in %s: %s"):format(location, filename)

  -- display-message updates the attached client's status line but never
  -- selects the originating window or pane.
  tmux_command({ "display-message", "-l", "-d", "3000", message })
  vim.notify(message, vim.log.levels.INFO, { title = "Claude Code" })
end

local function target_buffer_from_event(data)
  local window = data and data.target_window
  if window and vim.api.nvim_win_is_valid(window) then
    return vim.api.nvim_win_get_buf(window)
  end
  return find_loaded_buffer(data and data.file_path)
end

local function prune_sent_baselines(now)
  for path, baseline in pairs(state.sent_baselines) do
    if now - (baseline.captured_at or 0) > sent_baseline_ttl_seconds then
      state.sent_baselines[path] = nil
    end
  end
end

function M._on_send_complete(event)
  local data = event.data or {}
  local path = normalize_path(data.file_path)
  if not path then
    return
  end

  local now = os.time()
  prune_sent_baselines(now)

  local baseline = capture_baseline(path, find_loaded_buffer(path), "selection-send")
  baseline.captured_at = now
  state.sent_baselines[path] = baseline
end

function M._on_diff_opened(event)
  local data = event.data or {}
  local key = proposal_key(data)
  local path = normalize_path(data.file_path)
  local baseline = path and state.sent_baselines[path] or nil

  if baseline then
    state.sent_baselines[path] = nil
  else
    baseline = capture_baseline(path, target_buffer_from_event(data), "diff-open")
  end

  state.pending[key] = true
  state.baselines[key] = baseline
  update_tmux_marker()

  local diff_window = data.diff_window
  if diff_window and vim.api.nvim_win_is_valid(diff_window) then
    local proposal_buffer = vim.api.nvim_win_get_buf(diff_window)
    install_accept_guard(proposal_buffer, key, vim.api.nvim_create_augroup(group_name, { clear = false }))
    install_diff_mappings(proposal_buffer)
  else
    vim.notify(
      "Claude proposal opened without a valid diff window; acceptance is disabled.",
      vim.log.levels.ERROR,
      { title = "Claude proposal blocked" }
    )
  end

  notify_proposal(data)
end

function M._on_diff_closed(event)
  local key = proposal_key(event.data or {})
  state.pending[key] = nil
  state.baselines[key] = nil
  update_tmux_marker()
end

function M.accept_current()
  local proposal_buffer = vim.api.nvim_get_current_buf()
  local tab_name = vim.b[proposal_buffer].claudecode_diff_tab_name
  if not tab_name then
    vim.notify("No active Claude proposal in this buffer.", vim.log.levels.WARN)
    return false
  end
  return accept(tab_name, proposal_buffer)
end

function M.setup()
  if state.setup_done then
    return
  end
  state.setup_done = true

  local group = vim.api.nvim_create_augroup(group_name, { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ClaudeCodeSendComplete",
    desc = "Capture the source baseline when context is sent to Claude",
    callback = M._on_send_complete,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ClaudeCodeDiffOpened",
    desc = "Track and protect a newly opened Claude proposal",
    callback = M._on_diff_opened,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ClaudeCodeDiffClosed",
    desc = "Clear a resolved Claude proposal marker",
    callback = M._on_diff_closed,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "Clear this Neovim's Claude proposal marker",
    callback = function()
      state.pending = {}
      state.sent_baselines = {}
      update_tmux_marker()
    end,
  })

  -- Override the plugin's documented accept command with the same freshness
  -- boundary as :w. Rejection remains the plugin's native command.
  pcall(vim.api.nvim_del_user_command, "ClaudeCodeDiffAccept")
  vim.api.nvim_create_user_command("ClaudeCodeDiffAccept", function()
    M.accept_current()
  end, {
    desc = "Accept the current Claude diff when its source is fresh",
  })

  pcall(vim.api.nvim_del_user_command, "ClaudeCodeProposalStatus")
  vim.api.nvim_create_user_command("ClaudeCodeProposalStatus", function()
    local count = table_count(state.pending)
    vim.notify(
      ("%d pending Claude proposal%s"):format(count, count == 1 and "" or "s"),
      vim.log.levels.INFO,
      { title = "Claude Code" }
    )
  end, {
    desc = "Show the number of pending Claude proposals in this Neovim",
  })

  -- Clear a stale marker left by an earlier crashed instance in this window.
  update_tmux_marker()
end

-- Test hooks. They intentionally expose state transitions, not implementation
-- authority over real files.
M._state = state
M._disk_snapshot = disk_snapshot
M._buffer_hash = buffer_hash
M._freshness = freshness
M._update_tmux_marker = update_tmux_marker
M._prune_sent_baselines = prune_sent_baselines
M._sent_baseline_ttl_seconds = sent_baseline_ttl_seconds
M._pending_count = function()
  return table_count(state.pending)
end

return M
