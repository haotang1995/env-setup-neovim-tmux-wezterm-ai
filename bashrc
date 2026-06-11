# ~/.bashrc — managed by env-setup-neovim-tmux-wezterm-ai
# Edit the source at: $REPO/bashrc, re-run scripts/install.sh to push.
# Machine-local secrets / PATH tweaks belong in ~/.shellrc.local (gitignored).

# If not running interactively, don't do anything
case $- in
*i*) ;;
*) return ;;
esac

# History
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000

shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# chroot identifier (for the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

# Colored prompt when supported
case "$TERM" in
xterm-color | *-256color) color_prompt=yes ;;
esac

if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    color_prompt=yes
  else
    color_prompt=
  fi
fi

if [ "$color_prompt" = yes ]; then
  PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

case "$TERM" in
xterm* | rxvt*)
  PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
  ;;
*) ;;
esac

# ls / grep colors
if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
  alias ls='ls --color=auto'
  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

# Aliases — mirrored from zshrc for the rare case bash sticks around.
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status'
alias gd='git diff'
alias gds='git diff --staged'
alias gp='git push'
alias gl='git pull'
alias glog='git log --oneline --graph --all --decorate'
alias dc='docker compose'
alias dps='docker ps'
alias py='python3'
alias serve='python3 -m http.server'
alias ports='ss -tlnp'
alias reload='source ~/.bashrc'

alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi

# Programmable completion (the "tab autocomplete" you like in bash).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# kubectl/helm shortcuts (kpods, klogs, ksh, kgpu, knodes, kh, ...).
# Sourced before ~/.shellrc.local so the latter can override KNS / KUSER.
[ -f "$HOME/.k_shortcuts.sh" ] && source "$HOME/.k_shortcuts.sh"

# Machine-local: secrets, per-host PATH, work-only env vars.
# install.sh seeds this file from existing ~/.zshrc / ~/.bashrc on first run.
[ -f "$HOME/.shellrc.local" ] && source "$HOME/.shellrc.local"

# Auto-launch zsh if available (must come AFTER .shellrc.local so the zsh
# session inherits any exports defined there).
if [ -x /usr/bin/zsh ] && [ -z "$ZSH_VERSION" ]; then
  exec /usr/bin/zsh -l
fi
