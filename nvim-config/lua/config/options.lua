-- ~/.config/nvim/lua/config/options.lua
-- These are loaded BEFORE plugins by LazyVim

local opt = vim.opt

-- General
opt.clipboard = "unnamedplus" -- sync with system clipboard
opt.mouse = "a" -- enable mouse (useful for resizing, even if you avoid it)
opt.undofile = true -- persistent undo
opt.undolevels = 10000

-- Display
opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.wrap = false -- no line wrapping
opt.scrolloff = 8 -- keep 8 lines visible above/below cursor
opt.sidescrolloff = 8
opt.cursorline = true
opt.termguicolors = true

-- Indentation
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true -- case-sensitive if uppercase in pattern

-- Splits (open new splits below/right, matches tmux convention)
opt.splitbelow = true
opt.splitright = true

-- Completion
opt.completeopt = "menu,menuone,noselect"

-- LaTeX conceal (show α instead of \alpha, etc.)
opt.conceallevel = 2

-- Reduce update time (better for gitgutter, diagnostics)
opt.updatetime = 200
opt.timeoutlen = 300 -- which-key pops up faster

-- OSC 52 clipboard (works over SSH without X11 forwarding)
-- LazyVim enables this by default, but being explicit:
if vim.env.SSH_TTY then
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
      ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
      ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
    },
  }
end

-- Disable unused providers
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
-- vim.g.loaded_python3_provider = 0
vim.g.loaded_node_provider = 0 -- Copilot.lua handles node directly, doesn't need this
