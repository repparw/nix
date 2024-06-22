	# Ensure path doesn't have duplicates
	typeset -gU path
## Default editor to nvim
	export EDITOR='nvim'
	export VISUAL=$EDITOR

	export PATH=$HOME/.local/bin:$PATH
## fzf
	export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
	export FZF_DEFAULT_OPTS="--no-mouse --multi --select-1 --reverse --height 50% --inline-info --scheme=history"

	export LF_ICONS="di=📁:\
fi=📃:\
tw=🤝:\
ow=📂:\
ln=⛓:\
or=❌:\
ex=🎯:\
*.txt=✍:\
*.mom=✍:\
*.me=✍:\
*.ms=✍:\
*.png=🖼:\
*.webp=🖼:\
*.ico=🖼:\
*.jpg=📸:\
*.jpe=📸:\
*.jpeg=📸:\
*.gif=🖼:\
*.svg=🗺:\
*.tif=🖼:\
*.tiff=🖼:\
*.xcf=🖌:\
*.html=🌎:\
*.xml=📰:\
*.gpg=🔒:\
*.css=🎨:\
*.pdf=📚:\
*.djvu=📚:\
*.epub=📚:\
*.csv=📓:\
*.xlsx=📓:\
*.tex=📜:\
*.md=📘:\
*.r=📊:\
*.R=📊:\
*.rmd=📊:\
*.Rmd=📊:\
*.m=📊:\
*.mp3=🎵:\
*.opus=🎵:\
*.ogg=🎵:\
*.m4a=🎵:\
*.flac=🎼:\
*.wav=🎼:\
*.mkv=🎥:\
*.mp4=🎥:\
*.webm=🎥:\
*.mpeg=🎥:\
*.avi=🎥:\
*.mov=🎥:\
*.mpg=🎥:\
*.wmv=🎥:\
*.m4b=🎥:\
*.flv=🎥:\
*.zip=📦:\
*.rar=📦:\
*.7z=📦:\
*.tar.gz=📦:\
*.z64=🎮:\
*.v64=🎮:\
*.n64=🎮:\
*.gba=🎮:\
*.nes=🎮:\
*.gdi=🎮:\
*.1=ℹ:\
*.nfo=ℹ:\
*.info=ℹ:\
*.log=📙:\
*.iso=📀:\
*.img=📀:\
*.bib=🎓:\
*.ged=👪:\
*.part=💔:\
*.torrent=🔽:\
*.jar=♨:\
*.java=♨:\
"

# functions

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

  atuin-setup() {
  if ! which atuin &> /dev/null; then return 1; fi

  export ATUIN_NOBIND="true"
  eval "$(atuin init zsh)"
  fzf-atuin-history-widget() {
  local selected num
  setopt localoptions noglobsubst noposixbuiltins pipefail no_aliases 2>/dev/null

			# local atuin_opts="--cmd-only --limit ${ATUIN_LIMIT:-5000}"
			local atuin_opts="--cmd-only"
			local fzf_opts=(
			--no-mouse --multi --select-1 --reverse --height 50% --inline-info --scheme=history
			"--bind=ctrl-d:reload(atuin search $atuin_opts -c $PWD),ctrl-r:reload(atuin search $atuin_opts)"
		  )

		  selected=$(
		  eval "atuin search ${atuin_opts}" |
			fzf "${fzf_opts[@]}"
		  )
		  local ret=$?
		  if [ -n "$selected" ]; then
			# the += lets it insert at current pos instead of replacing
			LBUFFER+="${selected}"
		  fi
		  zle reset-prompt
		  return $ret
		}
		zle -N fzf-atuin-history-widget
		bindkey '^R' fzf-atuin-history-widget
	  }
# Functions END

  lfcd () {
	  # `command` is needed in case `lfcd` is aliased to `lf`
	  cd "$(command lf -print-last-dir "$@")"
  }
