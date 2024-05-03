#!/bin/zsh
#
# .zshrc - Zsh file loaded on interactive shell sessions.
#

# Zsh options
  setopt extended_glob

  # Histfile settings
  HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
  ## History ignore dups
  setopt EXTENDED_HISTORY
  setopt HIST_EXPIRE_DUPS_FIRST
  setopt HIST_IGNORE_DUPS
  setopt HIST_IGNORE_ALL_DUPS
  setopt HIST_IGNORE_SPACE
  setopt HIST_FIND_NO_DUPS
  setopt HIST_SAVE_NO_DUPS
  setopt HIST_BEEP

# Zsh options END

# Functions
  # lf with image previews and on-quit cd
  lf () {
	  LF_TEMPDIR="$(mktemp -d -t lf-tempdir-XXXXXX)"
	  LF_TEMPDIR="$LF_TEMPDIR" /bin/lf -last-dir-path="$LF_TEMPDIR/lastdir" "$@"
	  if [ "$(cat "$LF_TEMPDIR/cdtolastdir" 2>/dev/null)" = "1" ]; then
		  cd "$(cat "$LF_TEMPDIR/lastdir")"
	  fi
	  rm -r "$LF_TEMPDIR"
	  unset LF_TEMPDIR
  }
  # Use fd (https://github.com/sharkdp/fd) instead of the default find
  # command for listing path candidates.
  # - The first argument to the function ($1) is the base path to start traversal
  # - See the source code (completion.{bash,zsh}) for the details.
  _fzf_compgen_path() {
	fd --hidden --follow --exclude ".git" . "$1"
  }

  # Use fd to generate the list for directory completion
  _fzf_compgen_dir() {
	fd --type d --hidden --follow --exclude ".git" . "$1"
  }
# Functions END

# clone antidote if not present
[[ -d ${ZDOTDIR:-~}/.antidote ]] ||
  git clone https://github.com/mattmc3/antidote ${ZDOTDIR:-~}/.antidote

source ${ZDOTDIR:-$HOME}/.antidote/antidote.zsh

# set OMZ variables before loading OMZ plugins
export ZSH=$(antidote path ohmyzsh/ohmyzsh)
export ZSH_CACHE_DIR="$ZSH/cache"

antidote load # Default location ${ZDOTDIR:-$HOME}/.zsh_plugins.txt

# User configuration

## Aliases
if [ -f ${ZDOTDIR:-$HOME}/.aliases ]; then
	. ${ZDOTDIR:-$HOME}/.aliases
fi

# Load conflicting keybinds after zsh-vi-mode
# FZF ctrl-r and ctrl-t
zvm_after_init_commands+=('FZF_ALT_C_COMMAND= eval "$(fzf --zsh)"')
# Bind zsh-autosuggestions accept to ctrl-y
zvm_after_init_commands+=('bindkey "^Y" autosuggest-accept')

# If ssh and not in tmux, attach to ssh session
if [[ $- =~ i ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_TTY" ]]; then
  tmux new-session -A -s ssh
fi

## lscolors
  export LS_COLORS="di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
## Leave this here because omz overwrites this after .zprofile

zstyle ':completion:*' list-colors "di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
