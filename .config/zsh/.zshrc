#!/bin/zsh
#
# .zshrc - Zsh file loaded on interactive shell sessions.


# If ssh and not in tmux, attach to ssh session
if [[ $- =~ i ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_TTY" ]]; then
  tmux new-session -A -s ssh
fi

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.config/zsh/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# To customize prompt, run `p10k configure` or edit ~/.config/zsh/.p10k.zsh.
[[ ! -f ~/.config/zsh/.p10k.zsh ]] || source ~/.config/zsh/.p10k.zsh

# Zsh options
  setopt extended_glob
  # Histfile settings
  ## History ignore dups
  setopt EXTENDED_HISTORY
  setopt HIST_EXPIRE_DUPS_FIRST
  setopt HIST_IGNORE_DUPS
  setopt HIST_IGNORE_ALL_DUPS
  setopt HIST_IGNORE_SPACE
  setopt HIST_FIND_NO_DUPS
  setopt HIST_SAVE_NO_DUPS
  setopt HIST_BEEP
  HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history

# Zsh options END


[[ -f $HOME/.cargo/env ]] && source $HOME/.cargo/env

# clone antidote if not present

[[ -d ${XDG_CACHE_HOME:-$HOME/.cache}/antidote ]] ||
  git clone https://github.com/mattmc3/antidote ${XDG_CACHE_HOME:-$HOME/.cache}/antidote

source ${XDG_CACHE_HOME:-$HOME/.cache}/antidote/antidote.zsh

# set OMZ variables before loading OMZ plugins
export ZSH=$(antidote path ohmyzsh/ohmyzsh)

export ZSH_CACHE_DIR="$ZSH/cache"
# create completions dir if not present
[[ -d $ZSH_CACHE_DIR/completions ]] || mkdir -p $ZSH_CACHE_DIR/completions

antidote load # Default location ${ZDOTDIR:-$HOME}/.zsh_plugins.txt

# User configuration

# NVM setup
export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

## Aliases
if [ -f ${ZDOTDIR:-$HOME}/.aliases ]; then
	. ${ZDOTDIR:-$HOME}/.aliases
fi


# Load conflicting keybinds after zsh-vi-mode
# FZF ctrl-r and ctrl-t
zvm_after_init_commands+=('FZF_ALT_C_COMMAND= eval "$(fzf --zsh)"')


##FZF_CTRL_R_COMMAND= 
##zvm_after_init_commands+=('atuin-setup')


# zsh-autosuggestions accept to ctrl-y
zvm_after_init_commands+=('bindkey "^Y" autosuggest-accept')

# lfcd
zvm_after_init_commands+=("bindkey -s '^e' 'lf\n'")
zvm_after_init_commands+=("bindkey -s '^f' 'cdi\n'")

# history search with arrow keys
zvm_after_init_commands+=('bindkey "^[OA" history-substring-search-up')
zvm_after_init_commands+=('bindkey "^[OB" history-substring-search-down')

# history search on vi mode
zvm_after_init_commands+=('bindkey -M vicmd "k" history-substring-search-up')
zvm_after_init_commands+=('bindkey -M vicmd "j" history-substring-search-down')

## lscolors
  export LS_COLORS="di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
## Leave this here because omz overwrites this after .zprofile

zstyle ':completion:*' list-colors "di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"

source <(ng completion script)
