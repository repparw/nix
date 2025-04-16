{
  pkgs,
  config,
  lib,
  ...
}: {
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initExtraFirst = ''
      if [[ $- =~ i ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_TTY" ]]; then
          tmux new-session -A -s ssh
      fi

      if [[ -r "$XDG_CACHE_HOME/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "$XDG_CACHE_HOME/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi

      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
    '';
    initExtraBeforeCompInit = ''

      # create completions dir if not present
      [[ -d $ZSH_CACHE_DIR/completions ]] || mkdir -p $ZSH_CACHE_DIR/completions

    '';
    initExtra = ''
      [[ ! -f $ZDOTDIR/.p10k.zsh ]] || source $ZDOTDIR/.p10k.zsh

      if command -v kitty &> /dev/null; then alias ssh="kitten ssh"; fi

      # zsh-autosuggestions accept to ctrl-y
      zvm_after_init_commands+=('bindkey "^Y" autosuggest-accept')

      zvm_after_init_commands+=("bindkey -s '^f' 'cdi\n'")
      # history search with arrow keys
      zvm_after_init_commands+=('bindkey "^[OA" history-substring-search-up')
      zvm_after_init_commands+=('bindkey "^[OB" history-substring-search-down')
      zvm_after_init_commands+=('bindkey "^R" fzf-history-widget')

      # history search on vi mode
      zvm_after_init_commands+=('bindkey -M vicmd "k" history-substring-search-up')
      zvm_after_init_commands+=('bindkey -M vicmd "j" history-substring-search-down')

      export LS_COLORS="di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
      ## Leave this here because omz overwrites this after .zprofile
      zstyle ':completion:*' list-colors "di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
    '';
    shellAliases =
      {
        sudo = "sudo ";

        # Asks your passwords, becomes root, opens a interactive non login shell
        su = "sudo -s";

        v = "$EDITOR";

        obsinvim = "cd ~/Documents/obsidian/ && $EDITOR .; 1";

        # Nix
        vn = "cd ~/nix; $EDITOR flake.nix";

        nrs = "nh os switch";
        nup = "nh os switch -u";
        nupt = "nh os boot -u";

        x = "xdg-open";
        trash = "mv --force -t ~/.local/share/Trash ";

        ln = "ln -i";
        mv = "mv -i";
        rm = "rm -i";

        chown = "chown --preserve-root";
        chmod = "chmod --preserve-root";
        chgrp = "chgrp --preserve-root";

        mnt = "mount | awk -F' ' '{ printf \"%s\t%s\n\",\$1,\$3; }' | column -t | egrep ^/dev/ | sort";

        ping = "ping -c 5";

        meminfo = "free -h -l -t";
        cpuinfo = "lscpu";

        mkdir = "mkdir -pv";

        btctl = "bluetoothctl";

        sys = "systemctl";
        sysu = "sys --user";
        syslist = "systemctl list-unit-files";

        yd = "yt-dlp";
      }
      // (with pkgs; {
        feh = "${lib.getExe feh} -x -Z -. --image-bg black";

        top = "${lib.getExe pkgs.bottom} --theme gruvbox";
        diff = "${lib.getExe pkgs.colordiff}";
        cat = "${lib.getExe pkgs.bat}";
        df = "${lib.getExe pkgs.duf}";
        du = "${lib.getExe pkgs.dust}";

        rpi = "${lib.getExe' pkgs.mosh "mosh"} -P 60001 --ssh 'ssh -p 2222' rpi";
        pc = "${lib.getExe' pkgs.mosh "mosh"} -P 60000 --ssh 'ssh -p 10000' repparw@repparw.me";

        nq = "NQDIR=/tmp/nq ${lib.getExe' pkgs.nq "nq"}";
        tq = "NQDIR=/tmp/nq ${lib.getExe' pkgs.nq "tq"}";
        fq = "NQDIR=/tmp/nq ${lib.getExe' pkgs.nq "fq"}";
      });

    shellGlobalAliases = {
      G = " | ${lib.getExe pkgs.ripgrep}";
      L = " | less";
      W = " | wc -l";
      C = " | tr -d '\n' | wl-copy";
    };

    dotDir = ".config/zsh";
    history.path = "$ZDOTDIR/.zsh_history";
    antidote = {
      enable = true;
      plugins = [
        # OMZ completions requiring compinit
        "ohmyzsh/ohmyzsh path:plugins/podman/completions kind:fpath"

        # compinit
        "belak/zsh-utils path:completion"

        # ohmyzsh plugins
        "ohmyzsh/ohmyzsh path:lib"
        "ohmyzsh/ohmyzsh path:plugins/git"
        "ohmyzsh/ohmyzsh path:plugins/rsync"
        "ohmyzsh/ohmyzsh path:plugins/podman"
        "ohmyzsh/ohmyzsh path:plugins/tmux"

        "romkatv/powerlevel10k"

        "MichaelAquilina/zsh-you-should-use"

        # fish-like features
        "zsh-users/zsh-syntax-highlighting"
        "zsh-users/zsh-autosuggestions"
        "zsh-users/zsh-history-substring-search"
      ];
    };
  };
  home.file."${config.programs.zsh.dotDir}/.p10k.zsh".source = ../../source/p10k.zsh;
}
