{ pkgs, stable, ... }:

{
  xdg.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "$EDITOR";

    FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";
    FZF_DEFAULT_OPTS = "--no-mouse --multi --select-1 --reverse --height 50% --inline-info --scheme=history";

  };

  programs = {

    zsh = {
      enable = true;
      initExtraFirst = ''
        if [[ $- =~ i ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_TTY" ]]; then
          tmux new-session -A -s ssh
        fi

		if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
		  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
		fi
      '';
      initExtra = ''
		[[ ! -f $ZDOTDIR/.p10k.zsh ]] || source $ZDOTDIR/.p10k.zsh
		
        # zsh-autosuggestions accept to ctrl-y
        zvm_after_init_commands+=('bindkey "^Y" autosuggest-accept')

        lfcd() {
        	cd "$(command lf -print-last-dir "$@")"
        	  }


        # lfcd
        zvm_after_init_commands+=("bindkey -s '^e' 'lf\n'")
        zvm_after_init_commands+=("bindkey -s '^f' 'cdi\n'")

        # history search with arrow keys
        zvm_after_init_commands+=('bindkey "^[OA" history-substring-search-up')
        zvm_after_init_commands+=('bindkey "^[OB" history-substring-search-down')

        # history search on vi mode
        zvm_after_init_commands+=('bindkey -M vicmd "k" history-substring-search-up')
        zvm_after_init_commands+=('bindkey -M vicmd "j" history-substring-search-down')

		lfcd() {
			cd "$(command lf -print-last-dir "$@")"
			  }

		export LS_COLORS="di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
		## Leave this here because omz overwrites this after .zprofile
		zstyle ':completion:*' list-colors "di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
      '';
      shellAliases = {
        sudo = "sudo ";
        # check if kitty
        ssh = "kitten ssh";

        rpi = "ssh -p2222 dietpi@rpi";

        # check if not alpha?
        pc = " mosh -P 60000 --ssh 'ssh - p 10000' repparw@repparw.com.ar";

        f = "fzf";

        nq = "NQDIR=/tmp/nq nq";
        tq = "NQDIR=/tmp/nq tq";
        fq = "NQDIR=/tmp/nq fq";

        # Asks your passwords, becomes root, opens a interactive non login shell
        su = "sudo -s";

        # Make feh borderless and default to black image background color
        feh = "feh -x -Z -. --image-bg black";

        vim = "nvim";
        v = "nvim";

        vo = "cd ~/Documents/obsidian/ && nvim 02-Areas/Facu/Finales/TALLER.md; 1";
        # Configs
        vn = "v ~/.config/nvim/init.lua";

        # Nix
        nrb = "nh os switch";
        nrbt = "nh os boot";
        nup = "nh os switch -u";
        nupt = "nh os boot -u";

        x = "xdg-open";
        trash = "mv --force -t ~/.local/share/Trash ";
        ln = "ln -i";
        mv = "mv -i";

        chown = "chown --preserve-root";

        chmod = "chmod --preserve-root";

        chgrp = "chgrp --preserve-root";

        mnt = "mount | awk -F' ' '{ printf \"%s\t%s\n\",\$1,\$3; }' | column -t | egrep ^/dev/ | sort";

        path = "echo -e \${PATH//:/\\n}";

        # replace default utils, add checks if installed
        # add eza ls
        df = "duf";
        cat = "bat";
        diff = "colordiff";
        top = "btm --theme gruvbox";

        ping = "ping -c 5";

        meminfo = "free -h -l -t";
        cpuinfo = "lscpu";

        mkdir = "mkdir -pv";

        btctl = "bluetoothctl";

        sys = "systemctl";
        syslist = "systemctl list-unit-files";

        #yt
        yd = "yt-dlp";
        y = "ytf";
        ytf = "env YTFZF_ENABLE_FZF_DEFAULT_OPTS=1 ytfzf";
        ya = "ytf -a";
        yh = "ytf -H";
      };
      shellGlobalAliases = {
        G = " | rg";
        L = " | less";
        W = " | wc -l";
        C = " | tr -d '\n' | wl-copy";
      };

      dotDir = ".config/zsh";
      antidote = {
        enable = true;
        plugins = [

          # OMZ completions requiring compinit
          "ohmyzsh/ohmyzsh path:plugins/docker/completions kind:fpath"
          "ohmyzsh/ohmyzsh path:plugins/docker-compose/completions kind:fpath"

          # compinit
          "belak/zsh-utils path:completion"

          # ohmyzsh plugins
          "ohmyzsh/ohmyzsh path:lib"
          "ohmyzsh/ohmyzsh path:plugins/git"
          "ohmyzsh/ohmyzsh path:plugins/gh"
          "ohmyzsh/ohmyzsh path:plugins/rsync"
          "ohmyzsh/ohmyzsh path:plugins/docker"
          "ohmyzsh/ohmyzsh path:plugins/docker-compose"
          "ohmyzsh/ohmyzsh path:plugins/tmux"

          # powerlevel10k
          "romkatv/powerlevel10k"

          # Alias tips
          "MichaelAquilina/zsh-you-should-use"

          # fish-like features
          "zsh-users/zsh-syntax-highlighting"
          "zsh-users/zsh-autosuggestions"
          "zsh-users/zsh-history-substring-search"

          # zvm
          "jeffreytse/zsh-vi-mode"
        ];
      };
    };

    zoxide = {
      enable = true;
      options = [ "--cmd=cd" ];
    };

    eza.enable = true;

    git = {
      enable = true;
      userEmail = "ubritos@gmail.com";
      userName = "repparw";
      extraConfig = {
        rerere.enabled = true;
        pull.rebase = true;
      };
    };

    tmux = {
      enable = true;
      shell = "${pkgs.zsh}/bin/zsh";
      terminal = "xterm-kitty";
      historyLimit = 10000;
      prefix = "C-a";
      mouse = true;
      baseIndex = 1;
      newSession = true;
      keyMode = "vi";
      plugins = with pkgs.tmuxPlugins; [
        {
          plugin = power-theme;
          extraConfig = ''
            set -g @tmux_power_theme 'everforest'
            set -g @tmux_power_date_format '%F'
            set -g @tmux_power_time_format '%H:%M'
            set -g @tmux_power_date_icon ' '
            set -g @tmux_power_time_icon ' '
            set -g @tmux_power_user_icon ' '
            set -g @tmux_power_session_icon ' '
            set -g @tmux_power_right_arrow_icon     ''
            set -g @tmux_power_left_arrow_icon      ''
          '';
        }
        {
          plugin = resurrect;
          extraConfig = ''
            set -g @resurrect-dir "$XDG_DATA_HOME/tmux/resurrect"
          '';
        }
        {
          plugin = continuum;
          extraConfig = ''
            set -g @continuum-restore 'on'
          '';
        }

        pain-control
        #power-zoom
        #tmux-floax TODO
        vim-tmux-navigator
        yank
      ];
      extraConfig = ''
        		bind-key @ command-prompt -p "create pane from:" "join-pane -s ':%%'"

        # Shift Alt vim keys to switch windows
        		bind -n M-H previous-window
        		bind -n M-L next-window

        		set-option -g update-environment "DISPLAY WAYLAND_DISPLAY SSH_AUTH_SOCK"

        # keybindings
        		bind-key -T copy-mode-vi v send-keys -X begin-selection
        		bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
        		bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel

        		bind '"' split-window -v -c "#{pane_current_path}"
        		bind % split-window -h -c "#{pane_current_path}"

        		bind C-l send-keys 'C-l'
        		'';
    };

    ssh.addKeysToAgent = "yes";

  };

  home.packages =
    with pkgs;
    [
      # essentials
      nvim-pkg
      zsh
      curl
      wget
      unzip
      bluez
      jq
      tree
      ffmpeg
      imagemagick
      less
      base16-schemes
      yt-dlp
      fzf
      ytfzf

      # CLI tools
      playerctl
      rclone
      melt # ssh ed25519 keys to seed words
      ueberzugpp
      libqalculate
      gh

      fastfetch
      axel
      tlrc # tldr
      nq # Command queue

      lf
      vimv-rs # bulk rename
      pdfgrep
      catdoc # provides catppt and xls2csv

      tig

      # Modern replacements of basic tools
      bottom
      bat
      colordiff
      duf
      du-dust
      fd
      ripgrep
      tree

      manix

      nodejs # remove after porting nvim plugins to nix cfg
    ]
    ++ (
      with stable;
      [
      ]
    );
}
