-- ~/.config/nvim/lua/plugins/markdown.lua
-- Markdown: in-buffer rendering + browser preview
-- The LazyExtra lang.markdown handles render-markdown.nvim base setup.
-- This adds markdown-preview.nvim for live browser preview.

return {
  ---------------------------------------------------------------------------
  -- markdown-preview.nvim — live preview in browser
  ---------------------------------------------------------------------------
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = "cd app && npm install",
    init = function()
      vim.g.mkdp_auto_start = 0        -- don't auto-open browser
      vim.g.mkdp_auto_close = 1        -- close preview when leaving buffer
      vim.g.mkdp_refresh_slow = 0      -- real-time updates
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_theme = "dark"        -- match dark colorscheme

      -- KaTeX for math rendering
      vim.g.mkdp_preview_options = {
        katex = {},
        mermaid = {},                   -- also supports Mermaid diagrams
      }
    end,
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreviewToggle<CR>", desc = "Toggle markdown preview", ft = "markdown" },
    },
  },

  ---------------------------------------------------------------------------
  -- render-markdown.nvim overrides (prettify within Neovim buffer)
  ---------------------------------------------------------------------------
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      file_types = { "markdown", "Avante" },  -- also render in Avante chat
      heading = {
        enabled = true,
        icons = { "# ", "## ", "### ", "#### ", "##### ", "###### " },
      },
      checkbox = {
        enabled = true,
      },
      code = {
        enabled = true,
        style = "full",       -- background + border on code blocks
      },
    },
  },
}
