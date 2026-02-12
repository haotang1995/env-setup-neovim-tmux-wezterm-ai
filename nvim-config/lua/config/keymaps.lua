-- ~/.config/nvim/lua/config/keymaps.lua
-- Custom keymaps (loaded after LazyVim defaults)

local map = vim.keymap.set

-- Better escape (jk in insert mode)
map("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Move lines up/down in visual mode (LazyVim already has Alt+j/k, adding J/K too)
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Keep cursor centered when scrolling
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down (centered)" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up (centered)" })

-- Keep cursor centered when searching
map("n", "n", "nzzzv", { desc = "Next search result (centered)" })
map("n", "N", "Nzzzv", { desc = "Prev search result (centered)" })

-- Paste without overwriting register (paste over selection keeps original in register)
map("x", "<leader>p", [["_dP]], { desc = "Paste without yanking selection" })

-- Quick save
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })

-- Clear search highlights (LazyVim uses <Esc> for this, adding explicit binding too)
map("n", "<leader>nh", "<cmd>nohlsearch<CR>", { desc = "Clear search highlights" })

-- Quickfix navigation
map("n", "]q", "<cmd>cnext<CR>zz", { desc = "Next quickfix" })
map("n", "[q", "<cmd>cprev<CR>zz", { desc = "Prev quickfix" })

-- Comment toggle with \cc (like NERDCommenter)
map("n", "\\cc", "gcc", { desc = "Toggle comment line", remap = true })
map("v", "\\cc", "gc", { desc = "Toggle comment selection", remap = true })
