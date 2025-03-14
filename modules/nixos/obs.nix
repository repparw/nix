{ pkgs, ... }:
{
  programs.obs-studio = {
    enableVirtualCamera = true;
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-pipewire-audio-capture
      obs-backgroundremoval
    ];
  };
}
