{
  inputs,
  outputs,
  ...
}: {
  modifications = final: prev: {
    mpv = prev.mpv.override {
      scripts = with prev.mpvScripts; [
        mpv-webm
        mpris
        quality-menu
        sponsorblock-minimal
      ];
    };
  };

  # Keep the stable overlay as is
  stable = final: _: {
    stable = inputs.nixpkgs-stable.legacyPackages.${final.system};
  };
}
