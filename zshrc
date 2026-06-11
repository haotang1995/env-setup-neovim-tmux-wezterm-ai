# ~/.zshrc — managed by env-setup-neovim-tmux-wezterm-ai
# Edit the source at: $REPO/zshrc, re-run scripts/install.sh to push.
# Machine-local secrets / PATH tweaks belong in ~/.shellrc.local (gitignored).

export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

# Plugins — the "autocomplete" experience:
#   zsh-autosuggestions      → gray ghost-text from history (→ to accept)
#   zsh-syntax-highlighting  → live red/green command coloring
#   git/docker/python/node/npm/nvm → per-tool tab-completion
# zsh-autosuggestions and zsh-syntax-highlighting are bootstrapped by install.sh
# into $ZSH/custom/plugins/ if missing.
plugins=(git docker python node npm nvm zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# Preferred editor
export EDITOR='vim'

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Aliases — navigation
alias ..="cd .."
alias ...="cd ../.."
alias ll="ls -alFh"
alias la="ls -A"
alias l="ls -CF"

# Aliases — git shortcuts
alias gs="git status"
alias gd="git diff"
alias gds="git diff --staged"
alias gp="git push"
alias gl="git pull"
alias glog="git log --oneline --graph --all --decorate"

# Aliases — dev
alias dc="docker compose"
alias dps="docker ps"
alias py="python3"
alias serve="python3 -m http.server"
alias ports="ss -tlnp"

# Aliases — safety
alias rm="rm -i"
alias cp="cp -i"
alias mv="mv -i"

# Aliases — misc
alias reload="source ~/.zshrc"
alias myip="curl -s ifconfig.me"
alias weather="curl -s wttr.in/?format=3"

# kubectl/helm shortcuts (kpods, klogs, ksh, kgpu, knodes, kh, ...).
# Sourced before ~/.shellrc.local so the latter can override KNS / KUSER.
[ -f "$HOME/.k_shortcuts.sh" ] && source "$HOME/.k_shortcuts.sh"

# Machine-local: secrets, per-host PATH, work-only env vars.
# install.sh seeds this file from existing ~/.zshrc / ~/.bashrc on first run.
[ -f "$HOME/.shellrc.local" ] && source "$HOME/.shellrc.local"
