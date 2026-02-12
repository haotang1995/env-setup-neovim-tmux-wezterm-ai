# In-Terminal PDF Viewing with termpdf.py — Progress

## What's done

### 1. `nvim-config/lua/plugins/vimtex.lua` (in repo, deployed to `~/.config/nvim/`)
- Added `termpdf.py` as VimTeX `general` viewer fallback (between zathura and disabled)
- Added `<leader>vt` keymap (ft=tex) that opens termpdf.py in a tmux split or Neovim terminal
- Updated error message to point to GitHub instead of pip

### 2. `tmux.conf` (in repo, deployed to `~/.tmux.conf`, reloaded)
- Added `TERM` and `TERM_PROGRAM` to `update-environment` for Kitty graphics detection

### 3. `CLAUDE.md` (in repo only)
- Added `<leader>vt` to keymaps conventions
- Updated "Known issues & TODO" with install instructions and WezTerm+tmux caveat

## What's NOT yet deployed
- After fixing the install instructions in vimtex.lua and CLAUDE.md, the user rejected the redeploy `cp` command. So:
  - `~/.config/nvim/lua/plugins/vimtex.lua` still has the OLD error message: `"pip install pymupdf termpdf.py"`
  - The repo version has the CORRECT message: `"see github.com/dsanson/termpdf.py"`
- Need to re-run: `cp nvim-config/lua/plugins/vimtex.lua ~/.config/nvim/lua/plugins/vimtex.lua`

## termpdf.py installation
- `termpdf.py` is NOT on PyPI — must be cloned from https://github.com/dsanson/termpdf.py
- User's base conda env is Python 3.9; pymupdf 1.26.5 works but 1.26.6+ needs Python 3.10+
- Suggested install steps:
  ```bash
  pip3 install pymupdf
  git clone https://github.com/dsanson/termpdf.py ~/.local/share/termpdf.py
  ln -sf ~/.local/share/termpdf.py/termpdf.py ~/.local/bin/termpdf.py
  chmod +x ~/.local/share/termpdf.py/termpdf.py
  pip3 install -r ~/.local/share/termpdf.py/requirements.txt
  ```
- Ensure `~/.local/bin` is in PATH

## Known caveats
- Kitty graphics through tmux on WezTerm has rendering issues: [wezterm#4531](https://github.com/wezterm/wezterm/issues/4531)
- Works outside tmux or on native Kitty terminal
