-- Headless regression test for the tmux proposal marker.
-- Run from the repository root:
--
-- nvim --headless -u NONE \
--   --cmd "set rtp^=$PWD/nvim-config" \
--   -l nvim-config/tests/claude_tmux_marker_test.lua
--
-- The test drives both halves itself. The parent role starts a private tmux
-- server (its own socket, `-f /dev/null`) running this same file in the child
-- role, so it never touches the tmux session you are working in and needs no
-- external harness. Requires tmux on PATH; skips cleanly without it.
--
-- Channel names carry the parent pid because tmux remembers one un-awaited
-- `wait-for -S` per channel per server -- a fixed name could be pre-signalled
-- by an aborted run and make a later run pass without ever blocking.

local role = vim.env.CLAUDE_MARKER_TEST_ROLE or "parent"
local channel_prefix = vim.env.CLAUDE_MARKER_TEST_CHANNEL or ("claude-marker-" .. vim.fn.getpid())

local function channel(name)
  return channel_prefix .. "-" .. name
end

--------------------------------------------------------------------------
-- Child: runs inside a pane of the private tmux server.
--------------------------------------------------------------------------
if role == "child" then
  local policy = require("config.claude_proposals")

  policy._state.pending["tmux-test"] = true
  policy._update_tmux_marker()
  vim.fn.system({ "tmux", "wait-for", "-S", channel("ready") })

  vim.fn.system({ "tmux", "wait-for", channel("release") })

  policy._state.pending = {}
  policy._update_tmux_marker()
  vim.fn.system({ "tmux", "wait-for", "-S", channel("cleared") })

  -- Stay alive until the parent has read the cleared options: this is the last
  -- pane of the window, and tmux discards window options with the window.
  vim.fn.system({ "tmux", "wait-for", channel("finish") })
  return
end

--------------------------------------------------------------------------
-- Parent: owns the tmux server, inspects the window options, releases the
-- child, and reports.
--------------------------------------------------------------------------
if vim.fn.executable("tmux") ~= 1 then
  print("CLAUDE_TMUX_MARKER_TEST_SKIPPED tmux not on PATH")
  return
end

local repo = vim.fn.getcwd()
-- An explicit socket path rather than `-L name`: tmux leaves the socket file
-- behind after kill-server, and this one lives in Neovim's own temp directory
-- so it is removed with the process even if the test dies mid-run.
local socket = vim.fn.tempname()
local session = "marker"
-- A child that dies before signalling would leave `wait-for` blocked forever.
local timeout = vim.fn.executable("timeout") == 1 and "timeout"
  or (vim.fn.executable("gtimeout") == 1 and "gtimeout" or nil)

local function tmux(args)
  local command = { "tmux", "-S", socket }
  vim.list_extend(command, args)
  local output = vim.fn.system(command)
  return (output:gsub("%s+$", "")), vim.v.shell_error
end

local function cleanup()
  vim.fn.system({ "tmux", "-S", socket, "kill-server" })
  vim.fn.delete(socket)
end

local function fail(message)
  cleanup()
  error(message, 0)
end

local function wait_for(name)
  local command = { "tmux", "-S", socket, "wait-for", channel(name) }
  if timeout then
    table.insert(command, 1, "30")
    table.insert(command, 1, timeout)
  end
  vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    fail(("timed out waiting for the child on channel %q"):format(channel(name)))
  end
end

local function window_option(name)
  local value, code = tmux({ "show-options", "-w", "-v", "-t", session, name })
  if code ~= 0 then
    fail(("could not read window option %s"):format(name))
  end
  return value
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    cleanup()
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)), 0)
  end
end

local child = table.concat({
  ("CLAUDE_MARKER_TEST_ROLE=child CLAUDE_MARKER_TEST_CHANNEL=%s"):format(vim.fn.shellescape(channel_prefix)),
  vim.v.progpath,
  "--headless -u NONE",
  ("--cmd %s"):format(vim.fn.shellescape("set rtp^=" .. repo .. "/nvim-config")),
  ("-l %s"):format(vim.fn.shellescape(repo .. "/nvim-config/tests/claude_tmux_marker_test.lua")),
}, " ")

-- -f /dev/null keeps the user's tmux.conf (status line, base-index) out of it;
-- it applies because -L names a socket with no server on it yet.
local _, start_code = tmux({
  "-f",
  "/dev/null",
  "new-session",
  "-d",
  "-s",
  session,
  "-x",
  "80",
  "-y",
  "24",
  child,
})
if start_code ~= 0 then
  fail("could not start the private tmux server")
end

wait_for("ready")
assert_equal(window_option("@ai_proposal_count"), "1", "pending marker count")
assert_equal(window_option("@ai_proposal_marker"), " 🤖", "pending marker text")

tmux({ "wait-for", "-S", channel("release") })
wait_for("cleared")
local cleared_count = window_option("@ai_proposal_count")
local cleared_marker = window_option("@ai_proposal_marker")
tmux({ "wait-for", "-S", channel("finish") })
assert_equal(cleared_count, "0", "cleared marker count")
assert_equal(cleared_marker, "", "cleared marker text")

cleanup()
print("CLAUDE_TMUX_MARKER_TEST_OK")
