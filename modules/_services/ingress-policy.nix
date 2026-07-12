{ lib }:
{
  definitions,
  domain,
  serviceUrl,
}:
let
  routableDefinitions = lib.filterAttrs (
    name: service: service.hostname != null && name != "qbittorrent"
  ) definitions;
  proxyableDefinitions = lib.filterAttrs (_: service: service.port != null) definitions;
  unsupportedExternal = lib.attrNames (
    lib.filterAttrs (
      name: service:
      service.auth == "external"
      && (name != "qbittorrent" || service.hostname == null || service.port == null)
    ) definitions
  );
  hasServiceHost = name: builtins.hasAttr name definitions && definitions.${name}.hostname != null;
  serviceHost = name: "${definitions.${name}.hostname}.${domain}";
  apiServiceNames = lib.filter hasServiceHost [
    "bazarr"
    "paperless"
    "qbittorrent"
    "radarr"
    "miniflux"
    "sonarr"
  ];
  paperShareRules = lib.optional (hasServiceHost "paperless") {
    domain = [ (serviceHost "paperless") ];
    resources = [ "^/share/.*$" ];
    policy = "bypass";
  };
  apiBypassRules = lib.optional (apiServiceNames != [ ]) {
    domain = map serviceHost apiServiceNames;
    resources = [
      "^/api([/?].*)?$"
      "^/v1([/?].*)?$"
    ];
    policy = "bypass";
  };
  authMiddleware =
    service:
    lib.optional (builtins.elem service.auth [
      "one_factor"
      "two_factor"
    ]) "authelia";
  mkRouter =
    name: service:
    {
      rule = "Host(`${service.hostname}.${domain}`)";
      service = name;
    }
    // lib.optionalAttrs (authMiddleware service != [ ]) {
      middlewares = authMiddleware service;
    };
  mkBackend = name: {
    loadBalancer.servers = [ { url = serviceUrl name; } ];
  };
  modeRules =
    lib.mapAttrsToList
      (
        _: service:
        {
          domain = [ "${service.hostname}.${domain}" ];
          policy = service.auth;
        }
        //
          lib.optionalAttrs
            (builtins.elem service.auth [
              "one_factor"
              "two_factor"
            ])
            {
              subject = [ "group:admins" ];
            }
      )
      (lib.filterAttrs (_: service: service.hostname != null && service.auth != "external") definitions);
in
if unsupportedExternal != [ ] then
  throw "external ingress policy requires an explicit strategy: ${lib.concatStringsSep ", " unsupportedExternal}"
else
  {
    traefik = {
      routers =
        lib.mapAttrs mkRouter routableDefinitions
        // {
          home-router = {
            rule = "Host(`home.${domain}`)";
            service = "hass";
          };
          t3code = {
            rule = "Host(`code.${domain}`)";
            service = "t3code";
            middlewares = [ "authelia" ];
          };
          glance = {
            rule = "Host(`${domain}`)";
            service = "glance";
          };
        }
        // lib.optionalAttrs (hasServiceHost "qbittorrent") {
          qbittorrent = {
            rule = "Host(`${serviceHost "qbittorrent"}`) && !PathPrefix(`/api`)";
            service = "qbittorrent";
            middlewares = [ "qbit-auth" ];
          };
          qbittorrent-api = {
            rule = "Host(`${serviceHost "qbittorrent"}`) && PathPrefix(`/api`)";
            service = "qbittorrent";
          };
        };
      middlewares = {
        authelia.forwardAuth = {
          address = "${serviceUrl "authelia"}/api/authz/forward-auth";
          trustForwardHeader = true;
          authResponseHeaders = [
            "Remote-User"
            "Remote-Groups"
            "Remote-Email"
            "Remote-Name"
          ];
        };
        qbit-auth.chain.middlewares = [
          "authelia"
          "qbit-basic-auth"
        ];
        qbit-basic-auth.headers.customRequestHeaders.Authorization = "{{ env `QBIT_AUTH` }}";
      };
      services = lib.mapAttrs (name: _: mkBackend name) proxyableDefinitions // {
        hass.loadBalancer = {
          servers = [ { url = "http://192.168.0.4"; } ];
          healthCheck = {
            path = "/";
            interval = "10s";
            timeout = "3s";
          };
        };
        t3code.loadBalancer.servers = [ { url = "http://localhost:4097"; } ];
      };
    };

    authelia = {
      default_policy = "deny";
      rules =
        paperShareRules
        ++ apiBypassRules
        ++ [
          {
            domain = [ "home.${domain}" ];
            policy = "bypass";
          }
        ]
        ++ modeRules
        ++ [
          {
            domain = [ "*.${domain}" ];
            subject = [ "group:admins" ];
            policy = "one_factor";
          }
        ];
    };
  }
