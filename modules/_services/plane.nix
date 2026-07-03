{
  config,
  cfg,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  planeHost = "plane.${cfg.domain}";
  planeProxyPort = 3110;

  pkgs2405 = import inputs.nixpkgs-24-05 { system = pkgs.stdenv.hostPlatform.system; };

  planePkgWithOidc =
    let
      planeNixPath = "${inputs.plane-nix}";

      src = pkgs2405.runCommandNoCC "plane-oidc-src" { nativeBuildInputs = [ pkgs2405.perl ]; } ''
              cp -r ${inputs.torbenraab-plane-oidc} $out
              chmod -R +w $out
              cd $out
              patch -p1 < ${planeNixPath}/packages/plane/patches/poetry.patch
              patch -p1 < ${planeNixPath}/packages/plane/patches/runtime.patch
              patch -p1 < ${planeNixPath}/packages/plane/patches/x-forwarded-for.patch
              substituteInPlace apiserver/plane/authentication/provider/oauth/oidc.py \
                --replace-fail '"response_type": "code id_token"' '"response_type": "code"'
        perl -0pi -e 's/(if settings\.SKIP_ENV_VAR:.*?\n\s*for key in keys:\n)/$1            env_value = os.environ.get(key.get("key"))\n            if env_value is not None:\n                environment_list.append(env_value)\n                continue\n/s' apiserver/plane/license/utils/instance_value.py
        perl -0pi -e 's/(            ENABLE_EMAIL_PASSWORD,\n)(            SLACK_CLIENT_ID,)/$1            OIDC_AUTO,\n$2/' apiserver/plane/license/api/views/instance.py
        perl -0pi -e 's/(                \{\n                    "key": "SLACK_CLIENT_ID",)/                {\n                    "key": "OIDC_AUTO",\n                    "default": os.environ.get("OIDC_AUTO", "0"),\n                },\n$1/' apiserver/plane/license/api/views/instance.py
        perl -0pi -e 's/(        data\["is_email_password_enabled"\] = ENABLE_EMAIL_PASSWORD == "1"\n)/$1        data["is_oidc_auto"] = OIDC_AUTO == "1"\n/' apiserver/plane/license/api/views/instance.py
              substituteInPlace web/core/components/account/oauth/oauth-options.tsx \
                --replace-fail '  const isOAuthEnabled = (config && (config?.is_google_enabled || config?.is_github_enabled || config?.is_gitlab_enabled)) || false;' '  const isOAuthEnabled = (config && (config?.is_google_enabled || config?.is_github_enabled || config?.is_gitlab_enabled || config?.is_oidc_enabled)) || false;'
              substituteInPlace web/core/components/account/auth-forms/auth-root.tsx \
                --replace-fail '  const isSMTPConfigured = config?.is_smtp_configured || false;' '  const isSMTPConfigured = config?.is_smtp_configured || false;
        const isOidcOnly =
          !!config?.is_oidc_enabled &&
          !config?.is_google_enabled &&
          !config?.is_github_enabled &&
          !config?.is_gitlab_enabled &&
          !config?.is_email_password_enabled &&
          !config?.is_magic_login_enabled;' \
                --replace-fail '        {authStep === EAuthSteps.EMAIL && <AuthEmailForm defaultEmail={email} onSubmit={handleEmailVerification} />}' '        {!isOidcOnly && authStep === EAuthSteps.EMAIL && (
                <AuthEmailForm defaultEmail={email} onSubmit={handleEmailVerification} />
              )}' \
                --replace-fail '        {authStep === EAuthSteps.UNIQUE_CODE && (' '        {!isOidcOnly && authStep === EAuthSteps.UNIQUE_CODE && (' \
                --replace-fail '        {authStep === EAuthSteps.PASSWORD && (' '        {!isOidcOnly && authStep === EAuthSteps.PASSWORD && (' \
                --replace-fail '        <TermsAndConditions isSignUp={authMode === EAuthModes.SIGN_UP} />' '        {!isOidcOnly && <TermsAndConditions isSignUp={authMode === EAuthModes.SIGN_UP} />}'
      '';

      planePackageFn = import "${planeNixPath}/packages/plane/default.nix";
      lib' = pkgs2405.lib // {
        poetry2nix = inputs.poetry2nix.lib;
      };
    in
    planePackageFn {
      API_BASE_URL = "";
      lib = lib';
      pkgs = pkgs2405.extend (
        final: prev: {
          fetchFromGitHub =
            args: if args.owner == "makeplane" && args.repo == "plane" then src else prev.fetchFromGitHub args;
        }
      );
    };

  oidcEnv = {
    ENABLE_EMAIL_PASSWORD = "0";
    ENABLE_MAGIC_LINK_LOGIN = "0";
    IS_GITHUB_ENABLED = "0";
    IS_GITLAB_ENABLED = "0";
    IS_GOOGLE_ENABLED = "0";
    IS_OIDC_ENABLED = "1";
    OIDC_CLIENT_ID = "plane";
    OIDC_URL_AUTHORIZATION = "https://auth.${cfg.domain}/api/oidc/authorization";
    OIDC_URL_TOKEN = "https://auth.${cfg.domain}/api/oidc/token";
    OIDC_URL_USERINFO = "https://auth.${cfg.domain}/api/oidc/userinfo";
    OIDC_AUTO = "1";
  };

  # plane.nix generates the Celery worker/beat services with WorkingDirectory set
  # to stateDir. The generated command intends to pass --workdir to Celery, but
  # the line continuation after "--app plane" is missing upstream, so Celery
  # starts without the source tree on sys.path and fails with:
  # "Unable to load celery application. The module plane was not found."
  planePythonPath = lib.concatStringsSep ":" [
    "${planePkgWithOidc.src}/apiserver"
    "${planePkgWithOidc.apiserver}/${planePkgWithOidc.apiserver.python.sitePackages}"
  ];
in
{
  imports = [
    inputs.plane-nix.nixosModules."services/plane"
  ];

  modules.services.inventory.plane = {
    hostname = "plane";
    port = planeProxyPort;
    auth = "bypass";
    backup.path = "${cfg.configDir}/plane";
    monitor = true;
  };

  services.plane = {
    enable = true;
    package = planePkgWithOidc;
    domain = planeHost;
    stateDir = "${cfg.configDir}/plane/state";
    secretKeyFile = config.sops.secrets."plane/secretKey".path;

    database = {
      local = true;
      passwordFile = config.sops.secrets."plane/databasePassword".path;
    };

    storage = {
      credentialsFile = config.sops.secrets."plane/minioCredentials".path;
    };

    cache.local = true;
  };

  services.nginx.virtualHosts.${planeHost} = {
    enableACME = lib.mkForce false;
    forceSSL = lib.mkForce false;
    listen = lib.mkForce [
      {
        addr = "127.0.0.1";
        port = planeProxyPort;
        ssl = false;
      }
    ];
    extraConfig = "proxy_set_header X-Forwarded-Proto https;";
    locations."/api/" = {
      proxyPass = lib.mkForce "http://127.0.0.1:${toString config.services.plane.api.port}";
      proxyWebsockets = true;
      recommendedProxySettings = lib.mkForce false;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $hostname;
      '';
    };
    locations."/auth/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.plane.api.port}";
      proxyWebsockets = true;
      recommendedProxySettings = false;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $hostname;
      '';
    };
  };

  systemd.services.plane-api = {
    environment = oidcEnv // {
      APP_BASE_URL = lib.mkForce "http://plane.${cfg.domain}";
    };
    serviceConfig.EnvironmentFile = [ "-/tmp/plane-oidc-env" ];
    preStart = ''
      echo "OIDC_CLIENT_SECRET=$(cat ${
        config.sops.secrets."plane/oidcClientSecret".path
      })" > /tmp/plane-oidc-env
    '';
  };

  systemd.services.plane-web = {
    environment = {
      NEXT_PUBLIC_API_BASE_URL = lib.mkForce "http://plane.${cfg.domain}";
      APP_BASE_URL = lib.mkForce "http://plane.${cfg.domain}";
    };
  };

  systemd.services.plane-worker.environment.PYTHONPATH = lib.mkForce planePythonPath;
  systemd.services.plane-beat.environment.PYTHONPATH = lib.mkForce planePythonPath;
}
