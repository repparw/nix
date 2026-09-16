{
  lib,
  fetchurl,
}:
let
  # Helium strips update-ping parameters (it sends os=win with no
  # prodversion/lang), so the update server always answers
  # `<updatecheck status="noupdate"/>` and `external_update_url`
  # descriptors never install anything. Vendor the CRX files instead and
  # install via `external_crx` + `external_version` (verified: installs on
  # next browser start, no update-server round trip).
  #
  # To bump an extension: fetch the redirect URL below, read `version` from
  # the CRX zip payload's manifest.json, and update version + hash together
  # (they must match or Chromium ignores the descriptor).
  chromiumVersion = "152.0.7977.82";
  fetchCrx =
    {
      id,
      version,
      hash,
    }:
    fetchurl {
      name = "helium-extension-${id}-${version}.crx";
      url = "https://clients2.google.com/service/update2/crx?response=redirect&os=linux&arch=x64&nacl_arch=x86-64&prod=chromecrx&prodversion=${chromiumVersion}&lang=en&acceptformat=crx2,crx3&x=id%3D${id}%26installsource%3Dondemand%26uc";
      inherit hash;
    };
  extensions = [
    {
      id = "lmeddoobegbaiopohmpmmobpnpjifpii"; # Open in Firefox
      version = "0.5.0";
      hash = "sha256-e85yx9yT79Iu+zNuc7GbJt07xu3MSKsMAhP23XuvVFI=";
    }
    {
      id = "nngceckbapebfimnlniiiahkandclblb"; # Bitwarden
      version = "2026.8.0";
      hash = "sha256-0aWULZwjTQM4LamSeZMgVQZMquejLMmxV5QMhjFl1Z8=";
    }
    {
      id = "ddkjiahejlhfcafbddmgiahcphecmpfh"; # uBlock Origin Lite
      version = "2026.914.1325";
      hash = "sha256-O3hFq2zV7SQA98/W5FiNea6aPgCxgWfi701TrQV3Xtc=";
    }
    {
      id = "mnjggcdmjocbbbhaepdhchncahnbgone"; # SponsorBlock
      version = "6.1.6";
      hash = "sha256-VYf+K2qZRhAcoN3nxu/nanVcXuW21uY9/EjH9zbNtP8=";
    }
    {
      id = "enamippconapkdmgfgjchkhakpfinmaj"; # DeArrow
      version = "2.3.10";
      hash = "sha256-TDLGuKJs6KdnwGkjrnwAFgPxSj/uAwBE6CHZPYaclYA=";
    }
    {
      id = "bnomihfieiccainjcjblhegjgglakjdd"; # Improve YouTube!
      version = "4.2081";
      hash = "sha256-gcwEVzfNSFQSpBVYMwClKbCq6tXshMBddBt6OQD3yiw=";
    }
    {
      id = "dbepggeogbaibhgnhhndojpepiihcmeb"; # Vimium
      version = "2.4.2";
      hash = "sha256-MZjCaqcZvkYt6lhQUPvtm4uAYo1X6oihE7q/UzTFUXw=";
    }
  ];
in
lib.listToAttrs (
  map (ext: {
    name = ext.id;
    value = ext // {
      crx = fetchCrx ext;
    };
  }) extensions
)
