-- ~/.config/nvim/lua/plugins/tmux-navigator.lua
-- Seamless navigation between Neovim splits and tmux panes with Ctrl+hjkl

return {
  "christoomey/vim-tmux-navigator",
  lazy = false,
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    { "<C-h>", "<cmd>TmuxNavigateLeft<CR>",  desc = "Navigate left (Neovim/tmux)" },
    { "<C-j>", "<cmd>TmuxNavigateDown<CR>",  desc = "Navigate down (Neovim/tmux)" },
    { "<C-k>", "<cmd>TmuxNavigateUp<CR>",    desc = "Navigate up (Neovim/tmux)" },
    { "<C-l>", "<cmd>TmuxNavigateRight<CR>", desc = "Navigate right (Neovim/tmux)" },
    { "<C-\\>", "<cmd>TmuxNavigatePrevious<CR>", desc = "Navigate to previous pane" },
  },
}
