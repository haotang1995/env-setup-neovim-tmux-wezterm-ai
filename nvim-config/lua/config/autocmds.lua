-- ~/.config/nvim/lua/config/autocmds.lua
-- Custom autocommands

local autocmd = vim.api.nvim_create_autocmd

-- Auto-reload files changed by external tools (e.g., Claude Code, Aider in tmux pane)
autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  desc = "Auto-reload files modified externally",
  callback = function()
    if vim.o.buftype ~= "nofile" then
      vim.cmd("checktime")
    end
  end,
})

-- Highlight yanked text briefly
autocmd("TextYankPost", {
  desc = "Highlight on yank",
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 200 })
  end,
})

-- LaTeX: set local options for .tex files
autocmd("FileType", {
  pattern = "tex",
  desc = "LaTeX-specific settings",
  callback = function()
    vim.opt_local.wrap = true          -- wrap long lines in LaTeX
    vim.opt_local.linebreak = true     -- wrap at word boundaries
    vim.opt_local.spell = true         -- enable spell check
    vim.opt_local.spelllang = "en_us"
    vim.opt_local.textwidth = 0        -- don't hard-wrap
  end,
})

-- Markdown: similar treatment
autocmd("FileType", {
  pattern = "markdown",
  desc = "Markdown-specific settings",
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en_us"
    vim.opt_local.conceallevel = 2
  end,
})

-- Trim trailing whitespace on save (except for markdown where trailing spaces matter)
autocmd("BufWritePre", {
  desc = "Trim trailing whitespace",
  callback = function()
    if vim.bo.filetype ~= "markdown" then
      local save = vim.fn.winsaveview()
      vim.cmd([[%s/\s\+$//e]])
      vim.fn.winrestview(save)
    end
  end,
})
