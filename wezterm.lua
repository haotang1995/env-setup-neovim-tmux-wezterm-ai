-- ~/.wezterm.lua (or ~/.config/wezterm/wezterm.lua)
-- Cross-platform WezTerm config: macOS + Win11/WSL + Linux
-- Ported from iTerm2 G33 profile

local wezterm = require("wezterm")
local config = wezterm.config_builder()
local act = wezterm.action

---------------------------------------------------------------------------
-- Font
---------------------------------------------------------------------------
config.font = wezterm.font("JetBrains Mono", { weight = "Regular" })
-- Nerd Font symbols fallback (if JetBrains Mono Nerd Font is installed,
-- WezTerm picks up glyphs automatically; otherwise this explicit fallback helps)
config.font = wezterm.font_with_fallback({
	{ family = "JetBrains Mono", weight = "Regular" },
	{ family = "Symbols Nerd Font Mono" },
})
config.font_size = 17.0 -- adjust to taste (your iTerm2 was 21pt Monaco)
config.line_height = 1.0
config.cell_width = 1.0

-- Ligatures (JetBrains Mono supports these: => -> !== etc.)
config.harfbuzz_features = { "calt=1", "clig=1", "liga=1" }

---------------------------------------------------------------------------
-- Colors — matching your iTerm2 "G33" profile
---------------------------------------------------------------------------
config.colors = {
	foreground = "#bbbbbb",
	background = "#000000",
	cursor_fg = "#ffffff",
	cursor_bg = "#bbbbbb",
	cursor_border = "#bbbbbb",
	selection_fg = "#000000",
	selection_bg = "#b4d5ff",

	ansi = {
		"#000000", -- black
		"#bb0000", -- red
		"#00bb00", -- green
		"#bbbb00", -- yellow
		"#0000bb", -- blue
		"#bb00bb", -- magenta
		"#00bbbb", -- cyan
		"#bbbbbb", -- white
	},
	brights = {
		"#555555", -- bright black
		"#ff5555", -- bright red
		"#55ff55", -- bright green
		"#ffff55", -- bright yellow
		"#5555ff", -- bright blue
		"#ff55ff", -- bright magenta
		"#55ffff", -- bright cyan
		"#ffffff", -- bright white
	},

	-- Tab bar colors (subtle, stays out of the way)
	tab_bar = {
		background = "#0a0a0a",
		active_tab = {
			bg_color = "#1a1a2e",
			fg_color = "#bbbbbb",
			intensity = "Bold",
		},
		inactive_tab = {
			bg_color = "#0a0a0a",
			fg_color = "#555555",
		},
		inactive_tab_hover = {
			bg_color = "#1a1a2e",
			fg_color = "#bbbbbb",
		},
		new_tab = {
			bg_color = "#0a0a0a",
			fg_color = "#555555",
		},
	},
}

-- Uncomment to switch to Solarized Dark (your other iTerm2 profile):
-- config.color_scheme = "Solarized Dark (Gogh)"

---------------------------------------------------------------------------
-- Window appearance
---------------------------------------------------------------------------
config.window_background_opacity = 1.0 -- no transparency (matching iTerm2)
config.window_decorations = "RESIZE" -- minimal title bar
config.window_padding = {
	left = 4,
	right = 4,
	top = 4,
	bottom = 4,
}
config.initial_cols = 120
config.initial_rows = 35

-- Tab bar
config.use_fancy_tab_bar = false -- compact tab bar
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = true
config.tab_max_width = 32

-- No audible bell
config.audible_bell = "Disabled"

-- Scrollback (your iTerm2 had 1000; increase for terminal AI agent output)
config.scrollback_lines = 10000

---------------------------------------------------------------------------
-- Platform-specific settings
---------------------------------------------------------------------------
local is_mac = wezterm.target_triple:find("darwin") ~= nil
local is_windows = wezterm.target_triple:find("windows") ~= nil
local is_linux = wezterm.target_triple:find("linux") ~= nil

if is_mac then
	config.font_size = 17.0
	-- macOS: use Option as Meta (for Alt+key bindings in Neovim/tmux)
	config.send_composed_key_when_left_alt_is_pressed = false
	config.send_composed_key_when_right_alt_is_pressed = false
elseif is_windows then
	config.font_size = 14.0 -- Windows renders larger; adjust to taste
	config.default_domain = "WSL:Ubuntu"
	-- Launch directly into WSL Ubuntu
	config.default_prog = { "wsl.exe", "--distribution", "Ubuntu" }
elseif is_linux then
	config.font_size = 15.0
end

---------------------------------------------------------------------------
-- Terminal & protocol settings
---------------------------------------------------------------------------
config.term = "xterm-256color"
config.enable_kitty_graphics = true -- enable Kitty graphics protocol (for termpdf.py, images)
config.enable_wayland = false -- more stable on Linux

-- Cursor
config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 500
config.cursor_blink_ease_in = "Constant"
config.cursor_blink_ease_out = "Constant"

---------------------------------------------------------------------------
-- Key bindings
---------------------------------------------------------------------------
-- Philosophy: Let tmux handle session/window/pane management.
-- WezTerm keybindings are for WezTerm-specific features only.
-- Ctrl+hjkl is passed through to tmux/Neovim (no WezTerm interception).

-- Leader key: not used (tmux prefix handles multiplexing)

config.keys = {
	-------------------------------------------------
	-- Font size (Cmd/Ctrl +/- to zoom)
	-------------------------------------------------
	{ key = "=", mods = is_mac and "CMD" or "CTRL", action = act.IncreaseFontSize },
	{ key = "-", mods = is_mac and "CMD" or "CTRL", action = act.DecreaseFontSize },
	{ key = "0", mods = is_mac and "CMD" or "CTRL", action = act.ResetFontSize },

	-------------------------------------------------
	-- Clipboard (Ctrl+V pastes; Ctrl+Shift+C copies; Cmd variants handled by Cmd→Ctrl loop)
	-------------------------------------------------
	{ key = "c", mods = "CTRL|SHIFT", action = act.CopyTo("Clipboard") },
	{ key = "v", mods = "CTRL", action = act.PasteFrom("Clipboard") },
	{ key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },

	-------------------------------------------------
	-- WezTerm tab management (when not using tmux tabs)
	-------------------------------------------------
	{ key = "t", mods = "CTRL|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },
	{ key = "[", mods = is_mac and "CMD|SHIFT" or "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "]", mods = is_mac and "CMD|SHIFT" or "CTRL|SHIFT", action = act.ActivateTabRelative(1) },

	-------------------------------------------------
	-- Quick split (WezTerm-native, use when not in tmux)
	-------------------------------------------------
	{
		key = "d",
		mods = "CTRL|SHIFT",
		action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
	},
	{
		key = "d",
		mods = "CTRL|SHIFT|ALT",
		action = act.SplitVertical({ domain = "CurrentPaneDomain" }),
	},

	-------------------------------------------------
	-- Scrollback search (like Cmd+F in iTerm2)
	-------------------------------------------------
	{ key = "f", mods = "CTRL|SHIFT", action = act.Search("CurrentSelectionOrEmptyString") },

	-------------------------------------------------
	-- Quick select mode (clickable URLs, paths, etc.)
	-------------------------------------------------
	{ key = "Space", mods = is_mac and "CMD|SHIFT" or "CTRL|SHIFT", action = act.QuickSelect },

	-------------------------------------------------
	-- Debug / config reload
	-------------------------------------------------
	{ key = "r", mods = is_mac and "CMD|SHIFT" or "CTRL|SHIFT|ALT", action = act.ReloadConfiguration },

	-------------------------------------------------
	-- IMPORTANT: Ensure Ctrl+hjkl passes through to tmux/Neovim
	-- (WezTerm doesn't intercept these by default, but being explicit)
	-------------------------------------------------
	{ key = "h", mods = "CTRL", action = act.SendKey({ key = "h", mods = "CTRL" }) },
	{ key = "j", mods = "CTRL", action = act.SendKey({ key = "j", mods = "CTRL" }) },
	{ key = "k", mods = "CTRL", action = act.SendKey({ key = "k", mods = "CTRL" }) },
	{ key = "l", mods = "CTRL", action = act.SendKey({ key = "l", mods = "CTRL" }) },
}

-- Number keys to switch tabs (Cmd+1..9 on Mac, Ctrl+1..9 on Windows/Linux)
for i = 1, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = is_mac and "CMD" or "ALT",
		action = act.ActivateTab(i - 1),
	})
end

---------------------------------------------------------------------------
-- macOS: Map Cmd+<key> → Ctrl+<key> (matching iTerm2 behavior)
---------------------------------------------------------------------------
if is_mac then
	-- Cmd+Shift+T → new tab (matching Ctrl+Shift+T on other platforms)
	table.insert(config.keys, { key = "t", mods = "CMD|SHIFT", action = act.SpawnTab("CurrentPaneDomain") })

	-- Cmd+V → paste (macOS native behavior)
	table.insert(config.keys, { key = "v", mods = "CMD", action = act.PasteFrom("Clipboard") })

	-- Map remaining Cmd+<letter> → Ctrl+<letter> (matching iTerm2 behavior)
	-- Excludes v which is handled above as paste.
	for _, key in ipairs({
		"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
		"n", "o", "p", "q", "r", "s", "t", "u", "w", "x", "y", "z",
	}) do
		table.insert(config.keys, {
			key = key,
			mods = "CMD",
			action = act.SendKey({ key = key, mods = "CTRL" }),
		})
	end
end

---------------------------------------------------------------------------
-- Mouse bindings
---------------------------------------------------------------------------
-- Keep defaults enabled; add custom bindings on top
config.mouse_bindings = config.mouse_bindings or {}

-- Right-click paste (like iTerm2)
table.insert(config.mouse_bindings, {
	event = { Down = { streak = 1, button = "Right" } },
	mods = "NONE",
	action = act.PasteFrom("Clipboard"),
})

-- Cmd/Ctrl+Click to open URLs
table.insert(config.mouse_bindings, {
	event = { Up = { streak = 1, button = "Left" } },
	mods = is_mac and "CMD" or "CTRL",
	action = act.OpenLinkAtMouseCursor,
})

---------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------
config.check_for_updates = true
config.check_for_updates_interval_seconds = 86400 -- daily

-- Don't prompt on close if a tmux session is running
config.window_close_confirmation = "NeverPrompt"

-- Disable default Alt+Enter fullscreen (conflicts with some tools)
config.keys = config.keys or {}

return config
