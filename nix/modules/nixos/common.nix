{ pkgs, inputs, ... }:

{

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Argentina/Buenos_Aires";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_AR.UTF-8";
    LC_IDENTIFICATION = "es_AR.UTF-8";
    LC_MEASUREMENT = "es_AR.UTF-8";
    LC_MONETARY = "es_AR.UTF-8";
    LC_NAME = "es_AR.UTF-8";
    LC_NUMERIC = "es_AR.UTF-8";
    LC_PAPER = "es_AR.UTF-8";
    LC_TELEPHONE = "es_AR.UTF-8";
    LC_TIME = "es_AR.UTF-8";
  };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  services.keyd = {
    enable = true;
    keyboards.default.settings = {
      main = {
        capslock = "overload(control, esc)";
      };
    };
  };

  # Nerdfonts
  fonts = {
    packages = with pkgs; [ (nerdfonts.override { fonts = [ "FiraCode" ]; }) ];

    # Set default font
    fontconfig.defaultFonts = {
      "sansSerif" = [ "FiraCode Nerd Font" ];
      "serif" = [ "FiraCode Nerd Font" ];
      "monospace" = [ "FiraCode Nerd Font Mono" ];
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    zsh
    wget
  ];

  nixpkgs.overlays = [
    (self: super: { mpv = super.mpv.override { scripts = [ self.mpvScripts.mpris ]; }; })
    inputs.nixvim.overlays.default
  ];

  programs.zsh.enable = true;

  programs.mosh.enable = true;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    ports = [ 10000 ];
    settings.PasswordAuthentication = false;
  };

  programs.ssh.startAgent = true;

  # Enable sound with pipewire.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    wireplumber.enable = true;
    wireplumber.configPackages = [
      (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/11-disable-autoswitch.conf" ''
        wireplumber.settings = {
          bluetooth.autoswitch-to-headset-profile = false;
        }
      '')
      (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/20-bt.conf" ''
        monitor.bluez.properties = {
          bluez5.roles = [ a2dp_sink a2dp_source bap_sink bap_source ]
          bluez5.enable-hw-volume = false
        }
      '')
    ];
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  hardware.pulseaudio.enable = false;

  # Add xone?
  #hardware.xpadneo.enable = true;

  environment.etc = {
    # Creates /etc/nanorc
    "logid.cfg" = {
      text = ''
        devices: (
        {
        	name: "MX Vertical Advanced Ergonomic Mouse";
        	smartshift:
        	{
        		on: true;
        		threshold: 30;
        	};
        	hiresscroll:
        	{
        		hires: true;
        		invert: false;
        		target: false;
        	};
        	dpi: 1600;

        	buttons: (
        		{
        			cid: 0xfd;
        			action =
        			{
        				type: "Keypress";
        				keys: ["KEY_LEFTSHIFT", "KEY_LEFTMETA", "KEY_PRINT"];
        			};
        		}
        	);
        }
        );
      '';
    };
  };

  nix.settings.experimental-features = "nix-command flakes";
}
