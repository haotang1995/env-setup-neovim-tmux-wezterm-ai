-- ~/.config/nvim/lua/plugins/vimtex.lua
-- LaTeX: VimTeX overrides (the LazyExtra lang.tex handles the base setup)
-- This file customizes VimTeX for our workflow.

return {
  "lervag/vimtex",
  lazy = false,     -- VimTeX handles its own lazy-loading via autocommands
  init = function()
    -------------------------------------------------------------------------
    -- PDF Viewer
    -------------------------------------------------------------------------
    -- macOS: Skim (supports forward/inverse search)
    -- Linux with GUI: zathura (vim-like keybindings)
    -- Headless with termpdf.py: VimTeX "general" viewer (Kitty graphics)
    -- Fallback: disable viewer, compile only
    if vim.fn.has("mac") == 1 then
      vim.g.vimtex_view_method = "skim"
      vim.g.vimtex_view_skim_sync = 1       -- forward search after compile
      vim.g.vimtex_view_skim_activate = 1   -- bring Skim to front
    elseif vim.fn.executable("zathura") == 1 then
      vim.g.vimtex_view_method = "zathura"
    elseif vim.fn.executable("termpdf.py") == 1 then
      vim.g.vimtex_view_method = "general"
      vim.g.vimtex_view_general_viewer = "termpdf.py"
    else
      vim.g.vimtex_view_enabled = 0          -- no viewer available (SSH)
    end

    -------------------------------------------------------------------------
    -- Compiler
    -------------------------------------------------------------------------
    vim.g.vimtex_compiler_method = "latexmk"
    vim.g.vimtex_compiler_latexmk = {
      build_dir = "",                        -- same directory as source
      callback = 1,
      continuous = 1,                        -- recompile on save automatically
      executable = "latexmk",
      options = {
        "-verbose",
        "-file-line-error",
        "-synctex=1",                        -- needed for forward/inverse search
        "-interaction=nonstopmode",
      },
    }

    -------------------------------------------------------------------------
    -- Misc settings
    -------------------------------------------------------------------------
    vim.g.vimtex_quickfix_mode = 0           -- don't auto-open quickfix on warnings
    vim.g.vimtex_mappings_disable = { ["n"] = { "K" } }  -- don't override K (we use LSP hover)
    vim.g.vimtex_syntax_conceal_disable = 0  -- keep conceal enabled (α, ∫, etc.)

    -- Log parsing: ignore some noisy warnings
    vim.g.vimtex_log_ignore = {
      "Underfull",
      "Overfull",
      "specifier changed to",
      "Token not allowed in a PDF string",
    }

    -------------------------------------------------------------------------
    -- TexLab LSP keybinds (override VimTeX's K with LSP hover)
    -------------------------------------------------------------------------
    -- TexLab provides completions for \ref, \cite, etc.
    -- LazyVim's lang.tex extra handles the LSP setup.
    -- We just ensure K uses LSP hover instead of VimTeX doc.
  end,
  keys = {
    {
      "<leader>vt",
      function()
        if vim.fn.executable("termpdf.py") ~= 1 then
          vim.notify("termpdf.py not found (see github.com/dsanson/termpdf.py)", vim.log.levels.ERROR)
          return
        end

        -- Derive PDF path from VimTeX or the current .tex filename
        local pdf
        if vim.b.vimtex and vim.b.vimtex.out then
          pdf = type(vim.b.vimtex.out) == "function" and vim.b.vimtex.out() or vim.b.vimtex.out
        end
        if not pdf or pdf == "" then
          pdf = vim.fn.expand("%:p:r") .. ".pdf"
        end

        if vim.fn.filereadable(pdf) ~= 1 then
          vim.notify("PDF not found: " .. pdf .. " (compile first with \\ll)", vim.log.levels.WARN)
          return
        end

        local cmd = "termpdf.py " .. vim.fn.shellescape(pdf)

        if vim.env.TMUX then
          -- Open in a tmux split pane to the right
          vim.fn.system("tmux split-window -h -l 40% " .. vim.fn.shellescape(cmd))
        else
          -- Fallback: open in a Neovim terminal split
          vim.cmd("vsplit | terminal " .. cmd)
        end
      end,
      desc = "View PDF in termpdf.py",
      ft = "tex",
    },
  },
}
