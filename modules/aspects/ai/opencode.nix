{ den, ... }:
{
  den.aspects.ai.provides.opencode = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.opencode-desktop ];

        programs.opencode = {
          enable = true;
          enableMcpIntegration = true;
          skills = { };
          web = {
            enable = true;
            extraArgs = [
              "--port"
              "4096"
            ];
          };
          settings = {
            permission = {
              "*" = {
                "*" = "allow";
              };
            };
            formatter = false;
            provider = {
              oc-galo = {
                npm = "@ai-sdk/openai-compatible";
                name = "oc-galo";
                options = {
                  baseURL = "https://opencode.ai/zen/go/v1";
                };
                models = {
                  deepseek-v4-flash = {
                    name = "DeepSeek V4 Flash";
                  };
                  deepseek-v4-pro = {
                    name = "DeepSeek V4 Pro";
                  };
                  "kimi-k2.6" = {
                    name = "Kimi K2.6";
                  };
                };
              };
            };
          };
        };
      };
  };
}
