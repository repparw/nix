{
  bun,
  fetchurl,
  stdenv,
}:
# Bun 1.4.4 pins Brotli 1.2.1. OpenCode embeds the compiler's runtime.
bun.overrideAttrs (_: {
  version = "1.4.4";
  src = fetchurl {
    url = "https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/${
      {
        x86_64-linux = "bun-linux-x64-baseline.zip";
        aarch64-linux = "bun-linux-aarch64.zip";
        aarch64-darwin = "bun-darwin-aarch64.zip";
      }
      .${stdenv.hostPlatform.system}
    }";
    hash =
      {
        x86_64-linux = "sha256-4ERutVmVdy65iUvrrppr42jZhai5Jx7hJEhvmUbu3XY=";
        aarch64-linux = "sha256-uqa7NvUdblhWHgK76oJQOKnfRU9nPW13bou/hvjHhQ4=";
        aarch64-darwin = "sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=";
      }
      .${stdenv.hostPlatform.system};
  };
})
