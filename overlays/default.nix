{
  inputs,
  outputs,
  ...
}: {
  modifications = final: prev: {
    mpv = prev.mpv.override {
      scripts = with final.mpvScripts; [
        mpv-webm
        mpris
        quality-menu
        sponsorblock-minimal
      ];
    };
  };

  stable = final: _: {
    stable = inputs.nixpkgs-stable.legacyPackages.${final.system};
  };
}
