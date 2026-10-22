{
  callPackage,
  path,
  fetchurl,
  brotli,
  c-ares,
  openssl,
  python3,
  nodejs-slim_24,
}:
let
  secureBrotli = brotli.overrideAttrs (old: {
    patches = old.patches ++ [
      (fetchurl {
        url = "https://github.com/google/brotli/commit/0ed4268a4401abcb4472096340477cf4af7d1a2b.patch?full_index=1";
        hash = "sha256-1vliUJAAIj3vcGKVgim9CEV+XgMuftDR2U+3kLBUsfw=";
      })
    ];
  });
  secureCares = c-ares.overrideAttrs (_: {
    version = "1.34.9";
    src = fetchurl {
      url = "https://github.com/c-ares/c-ares/releases/download/v1.34.9/c-ares-1.34.9.tar.gz";
      hash = "sha256-k2S3ChLrWaBoMPtIjZNX+QEA3/DZiyPqNZOhg9Q+by8=";
    };
  });
  secureOpenssl = openssl.overrideAttrs (_: {
    version = "3.5.9";
    src = fetchurl {
      url = "https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz";
      sha256 = "603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a";
    };
  });
in
(callPackage (path + "/pkgs/development/web/nodejs/nodejs.nix") {
  python = python3;
  brotli = secureBrotli;
  c-ares = secureCares;
  openssl = secureOpenssl;
})
  {
    version = "24.22.1";
    sha256 = "4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231";
    inherit (nodejs-slim_24) patches;
  }
