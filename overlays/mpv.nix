final: prev: {
  mpv = prev.mpv.override {
    scripts = with final.mpvScripts; [
      mpv-webm
      mpris
      quality-menu
      sponsorblock-minimal
    ];
  };
}
