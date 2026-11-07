let
  mkExtractorWatcher =
    {
      slug,
      label,
      url,
      fetchUrl,
      extractor,
      displayTemplate,
      message,
    }:
    {
      inherit
        slug
        label
        url
        fetchUrl
        extractor
        displayTemplate
        message
        ;
      mode = "extractor";
    };
in
[
  (
    (mkExtractorWatcher {
      slug = "nixpkgs-security-fleet";
      label = "Accepted Nixpkgs security issues for fleet packages";
      url = "https://tracker.security.nixos.org/issues";
      fetchUrl = "https://tracker.security.nixos.org/api/v1/issues?expand=suggestions";
      extractor = "nixpkgsSecurityIssues";
      displayTemplate = "nixpkgsSecurityIssues";
      message = "New accepted Nixpkgs security issues for fleet packages";
    })
    // {
      fetcher = "curl";
      # Suggestion payloads embed full per-package version and
      # maintainer metadata; single pages now exceed the 2 MiB default.
      maxResponseBytes = 16 * 1024 * 1024;
      packages = [
        "authelia"
        "bazarr"
        "brotli"
        "bun"
        "c-ares"
        "chromium"
        "electron"
        "firefox"
        "git"
        "glibc"
        "home-assistant"
        "jellyfin"
        "linux"
        "miniflux"
        "nix"
        "nodejs_24"
        "nodejs-slim_24"
        "openssh"
        "openssl"
        "paperless-ngx"
        "postgresql"
        "prowlarr"
        "python3"
        "qbittorrent"
        "radarr"
        "redis"
        "sonarr"
        "systemd"
        "traefik"
        "wireguard-tools"
      ];
    }
  )
  (mkExtractorWatcher {
    slug = "8bitdo-ultimate-2c-firmware";
    label = "8BitDo Ultimate 2C firmware";
    url = "https://support.8bitdo.com/#ultimate-2c-wireless";
    fetchUrl = "https://support.8bitdo.com/";
    extractor = "eightBitdoUltimate2cFirmware";
    displayTemplate = "8bitdoFirmware";
    message = "8BitDo Ultimate 2C firmware changed: {{previous}} -> {{current}}\n{{url}}";
  })
  (
    mkExtractorWatcher {
      slug = "nixos-latest-release-notes";
      label = "NixOS latest release notes";
      url = "https://nixos.org/manual/nixos/unstable/release-notes";
      fetchUrl = "https://nixos.org/manual/nixos/unstable/release-notes";
      extractor = "nixosReleaseChanges";
      displayTemplate = "nixosReleaseChanges";
      message = "**NixOS {{version}} release notes updated**\n{{url}}\n\n**New modules:**\n{{newModules}}\n\n**Breaking changes:**\n{{breakingChanges}}\n\n**Other notable changes:**\n{{otherChanges}}";
    }
    // {
      # Unstable release notes are a single accumulating page, 1.6 MiB
      # as of 2026-11-05 and growing toward the 2 MiB default.
      maxResponseBytes = 16 * 1024 * 1024;
    }
  )
];
