# Theme (dstufft with added time)
function prompt_char {
    git branch >/dev/null 2>/dev/null && echo '±' && return
    echo '○'
}

function virtualenv_info {
    [ $VIRTUAL_ENV ] && echo '('`basename $VIRTUAL_ENV`') '
}

export PROMPT='
%{$fg[magenta]%}%n%{$reset_color%} at %{$fg[yellow]%}%m%{$reset_color%} in %{$fg_bold[green]%}%~%{$reset_color%}$(git_prompt_info)
$(virtualenv_info)$(prompt_char) '

export RPROMPT='%{$fg[green]%}[%*]%{$reset_color%}'

export ZSH_THEME_GIT_PROMPT_PREFIX=' on %{$fg[magenta]%}'
export ZSH_THEME_GIT_PROMPT_SUFFIX='%{$reset_color%}'
export ZSH_THEME_GIT_PROMPT_DIRTY='%{$fg[green]%}!'
export ZSH_THEME_GIT_PROMPT_UNTRACKED='%{$fg[green]%}?'
export ZSH_THEME_GIT_PROMPT_CLEAN=''

# Add local path
	export PATH=/home/repparw/.cargo/bin:/usr/local/cuda/bin:/home/repparw/go/bin:/home/repparw/.local/bin:$PATH

	export HISTCONTROL=ignoreboth:erasedups
## Default editor to nvim
	export EDITOR='nvim'
	export VISUAL=$EDITOR

## fzf
	export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"

	export FZF_DEFAULT_OPTS="--no-mouse --multi --select-1 --reverse --height 50% --inline-info --scheme=history"

# Path to your oh-my-zsh installation.
	export ZSH="/home/repparw/.oh-my-zsh"

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
