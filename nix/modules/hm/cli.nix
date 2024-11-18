{ pkgs, stable, ... }:

{
  imports = [
    ./zsh.nix
  ];

  xdg.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "$EDITOR";
    YTFZF_ENABLE_FZF_DEFAULT_OPTS = 1;
    ZSH_CACHE_DIR = "$XDG_CACHE_HOME/zsh";
    RIP_GRAVEYARD = "${XDG_DATA_HOME:-$HOME/.local/share}/Trash";
  };

  programs = {
    fd = {
      enable = true;
      hidden = true;
    };

    lf = {
      enable = true;
	  previewer.source = pkgs.writeShellScript "lf_kitty_preview" ''
		file=$1
		w=$2
		h=$3
		x=$4
		y=$5

		if [[ "$( file -Lb --mime-type "$file")" =~ ^image ]]; then
			kitty +kitten icat --silent --stdin no --transfer-mode file --place "${w}x${h}@${x}x${y}" "$file" < /dev/null > /dev/tty
			exit 1
		fi

		pistol "$file"
'';
      settings = {
        shell = "zsh";
        shellopts = "-eu";
        ifs = "\n";
        scrolloff = 10;
        hidden = true;
        drawbox = true;
        icons = true;
        period = 1;

        cmd = [ "trash $rip $fx" ];

		cleaner = pkgs.writeShellScript "lf_kitty_clean" ''
		  kitty +kitten icat --clear --stdin no --silent --transfer-mode file < /dev/null > /dev/tty
		'';

      };
      keybindings = {
        D = "trash";
        U = "!du -sh";
        b = "bulk";
        q = "quit";
      };

    };
    programs.zsh.initExtra = ''
      lfcd() {
      	cd "$(command lf -print-last-dir "$@")"
      	  }
      zvm_after_init_commands+=("bindkey -s '^e' 'lfcd\n'")
    '';
    home.file.".config/lf/icons".text = ''
      ln             # LINK
      or             # ORPHAN
      tw      t       # STICKY_OTHER_WRITABLE
      ow             # OTHER_WRITABLE
      st      t       # STICKY
      di             # DIR
      pi      p       # FIFO
      so      s       # SOCK
      bd      b       # BLK
      cd      c       # CHR
      su      u       # SETUID
      sg      g       # SETGID
      ex             # EXEC
      fi             # FILE

      *.styl          
      *.sass          
      *.scss          
      *.htm           
      *.html          
      *.slim          
      *.haml          
      *.ejs           
      *.css           
      *.less          
      *.md            
      *.mdx           
      *.markdown      
      *.rmd           
      *.json          
      *.webmanifest   
      *.js            
      *.mjs           
      *.jsx           
      *.rb            
      *.gemspec       
      *.rake          
      *.php           
      *.py            
      *.pyc           
      *.pyo           
      *.pyd           
      *.coffee        
      *.mustache      
      *.hbs           
      *.conf          
      *.ini           
      *.yml           
      *.yaml          
      *.toml          
      *.bat           
      *.mk            
      *.jpg           
      *.jpeg          
      *.bmp           
      *.png           
      *.webp          
      *.gif           
      *.ico           
      *.twig          
      *.cpp           
      *.c++           
      *.cxx           
      *.cc            
      *.cp            
      *.c             
      *.cs            󰌛
      *.h             
      *.hh            
      *.hpp           
      *.hxx           
      *.hs            
      *.lhs           
      *.nix           
      *.lua           
      *.java          
      *.sh            
      *.fish          
      *.bash          
      *.zsh           
      *.ksh           
      *.csh           
      *.awk           
      *.ps1           
      *.ml            λ
      *.mli           λ
      *.diff          
      *.db            
      *.sql           
      *.dump          
      *.clj           
      *.cljc          
      *.cljs          
      *.edn           
      *.scala         
      *.go            
      *.dart          
      *.xul           
      *.sln           
      *.suo           
      *.pl            
      *.pm            
      *.t             
      *.rss           
      '*.f#'          
      *.fsscript      
      *.fsx           
      *.fs            
      *.fsi           
      *.rs            
      *.rlib          
      *.d             
      *.erl           
      *.hrl           
      *.ex            
      *.exs           
      *.eex           
      *.leex          
      *.heex          
      *.vim           
      *.ai            
      *.psd           
      *.psb           
      *.ts            
      *.tsx           
      *.jl            
      *.pp            
      *.vue           
      *.elm           
      *.swift         
      *.xcplayground  
      *.tex           󰙩
      *.r             󰟔
      *.rproj         󰗆
      *.sol           󰡪
      *.pem           
      *gruntfile.coffee       
      *gruntfile.js           
      *gruntfile.ls           
      *gulpfile.coffee        
      *gulpfile.js            
      *gulpfile.ls            
      *mix.lock               
      *dropbox                
      *.ds_store              
      *.gitconfig             
      *.gitignore             
      *.gitattributes         
      *.gitlab-ci.yml         
      *.bashrc                
      *.zshrc                 
      *.zshenv                
      *.zprofile              
      *.vimrc                 
      *.gvimrc                
      *_vimrc                 
      *_gvimrc                
      *.bashprofile           
      *favicon.ico            
      *license                
      *node_modules           
      *react.jsx              
      *procfile               
      *dockerfile             
      *docker-compose.yml     
      *docker-compose.yaml    
      *compose.yml            
      *compose.yaml           
      *rakefile               
      *config.ru              
      *gemfile                
      *makefile               
      *cmakelists.txt         
      *robots.txt             󰚩
      *Gruntfile.coffee       
      *Gruntfile.js           
      *Gruntfile.ls           
      *Gulpfile.coffee        
      *Gulpfile.js            
      *Gulpfile.ls            
      *Dropbox                
      *.DS_Store              
      *LICENSE                
      *React.jsx              
      *Procfile               
      *Dockerfile             
      *Docker-compose.yml     
      *Docker-compose.yaml    
      *Rakefile               
      *Gemfile                
      *Makefile               
      *CMakeLists.txt         
      *jquery.min.js          
      *angular.min.js         
      *backbone.min.js        
      *require.min.js         
      *materialize.min.js     
      *materialize.min.css    
      *mootools.min.js        
      *vimrc                  
      Vagrantfile             
      *.tar   
      *.tgz   
      *.arc   
      *.arj   
      *.taz   
      *.lha   
      *.lz4   
      *.lzh   
      *.lzma  
      *.tlz   
      *.txz   
      *.tzo   
      *.t7z   
      *.zip   
      *.z     
      *.dz    
      *.gz    
      *.lrz   
      *.lz    
      *.lzo   
      *.xz    
      *.zst   
      *.tzst  
      *.bz2   
      *.bz    
      *.tbz   
      *.tbz2  
      *.tz    
      *.deb   
      *.rpm   
      *.jar   
      *.war   
      *.ear   
      *.sar   
      *.rar   
      *.alz   
      *.ace   
      *.zoo   
      *.cpio  
      *.7z    
      *.rz    
      *.cab   
      *.wim   
      *.swm   
      *.dwm   
      *.esd   
      *.jpg   
      *.jpeg  
      *.mjpg  
      *.mjpeg 
      *.gif   
      *.bmp   
      *.pbm   
      *.pgm   
      *.ppm   
      *.tga   
      *.xbm   
      *.xpm   
      *.tif   
      *.tiff  
      *.png   
      *.svg   
      *.svgz  
      *.mng   
      *.pcx   
      *.mov   
      *.mpg   
      *.mpeg  
      *.m2v   
      *.mkv   
      *.webm  
      *.ogm   
      *.mp4   
      *.m4v   
      *.mp4v  
      *.vob   
      *.qt    
      *.nuv   
      *.wmv   
      *.asf   
      *.rm    
      *.rmvb  
      *.flc   
      *.avi   
      *.fli   
      *.flv   
      *.gl    
      *.dl    
      *.xcf   
      *.xwd   
      *.yuv   
      *.cgm   
      *.emf   
      *.ogv   
      *.ogx   
      *.aac   
      *.au    
      *.flac  
      *.m4a   
      *.mid   
      *.midi  
      *.mka   
      *.mp3   
      *.mpc   
      *.ogg   
      *.ra    
      *.wav   
      *.oga   
      *.opus  
      *.spx   
      *.xspf  
      *.pdf   
    '';

    fzf = {
      enable = true;
      defaultOptions = [
        "--no-mouse"
        "--multi"
        "--select-1"
        "--reverse"
        "--height 50%"
        "--inline-info"
        "--scheme=history"
      ];
      defaultCommand = "fd --type f --hidden --follow --exclude .git";
    };

    gh = {
      enable = true;
      extensions = [ pkgs.gh-copilot ];
      settings.git_protocol = "ssh";
    };

    zoxide = {
      enable = true;
      options = [ "--cmd=cd" ];
    };

    eza = {
      enable = true;
      extraOptions = [ "--icons" ];
    };

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

      fastfetch
      axel
      tlrc # tldr
      nq # Command queue

	  pistol # preview images lf+kitty

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
      ripgrep
      tree
      rip2

      manix

      nodejs # TODO remove after finishing tp proy
    ]
    ++ (
      with stable;
      [
      ]
    );
}
