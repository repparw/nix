{
  bun,
  fetchurl,
  stdenv,
}:
# Last bun whose `bun install` applies the OpenCode 2.0.26 lockfile patches.
# The channel's bun moved to 1.4.4 on the next snapshot after this pin and its
# patchedDependencies handling rejects `patches/@silvia-odwyer/photon-node`
# (hunk #10 no longer applies to photon_rs.js), failing the opencode node_modules
# fixed-output derivation. This pin lasts only while the vendored 2.0.26
# packaging (PR #222) remains; the overlay retirement itself is issue #229.
bun.overrideAttrs (_: {
  version = "1.4.2";
  src = fetchurl {
    url = "https://github.com/oven-sh/bun/releases/download/bun-v1.4.2/${
      {
        x86_64-linux = "bun-linux-x64-baseline.zip";
        aarch64-linux = "bun-linux-aarch64.zip";
        aarch64-darwin = "bun-darwin-aarch64.zip";
      }
      .${stdenv.hostPlatform.system}
    }";
    hash =
      {
        x86_64-linux = "sha256-xngEDxT+BEDrg503y9DOTAUaMtpygGrJfeamqra/co8=";
        aarch64-linux = "sha256-VDKLvC2cjgyfiSxUTWbFeoO4QTnjSQnl7oF1jxrI/ac=";
        aarch64-darwin = "sha256-kJh6OhbX21VtiGrD1VHnttPt8KHPQ6yu1iLoZ2vh0S8=";
      }
      .${stdenv.hostPlatform.system};
  };
})
