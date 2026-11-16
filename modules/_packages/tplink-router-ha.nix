{
  lib,
  fetchFromGitHub,
  buildHomeAssistantComponent,
  tplinkrouterc6u,
}:

# TP-Link Router integration providing device_tracker entities from the
# router's connected-client inventory. Declarative install replaces the
# HACS-managed copy; the config entry (polling and timeout settings,
# credentials) stays in the Home Assistant storage on the host.
buildHomeAssistantComponent rec {
  owner = "AlexandrErohin";
  domain = "tplink_router";
  version = "2.46.0";

  src = fetchFromGitHub {
    owner = "AlexandrErohin";
    repo = "home-assistant-tplink-router";
    tag = "v${version}";
    hash = "sha256-Mc/Y3RwglF0oFoofYBnu1pNSWyhPFn83SbakZPuezX4=";
  };

  # The manifest pins tplinkrouterc6u==5.40.0; pass the custom package from
  # the homeassistant aspect so the runtime import resolves to it.
  dependencies = [ tplinkrouterc6u ];

  meta = {
    changelog = "https://github.com/AlexandrErohin/home-assistant-tplink-router/releases/tag/v${version}";
    description = "TP-Link Router integration for Home Assistant";
    homepage = "https://github.com/AlexandrErohin/home-assistant-tplink-router";
    license = lib.licenses.mit;
  };
}
