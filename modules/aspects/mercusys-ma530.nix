{ ... }:
{
  den.aspects.mercusys-ma530 = {
    nixos =
      { config, pkgs, ... }:
      let
        modDirVersion = config.boot.kernelPackages.kernel.modDirVersion;
        btusb-mercusys-ma530 = pkgs.stdenv.mkDerivation {
          pname = "btusb-mercusys-ma530";
          version = config.boot.kernelPackages.kernel.version;

          src = config.boot.kernelPackages.kernel.src;

          patches = [ ./mercusys-ma530-btusb.patch ];

          nativeBuildInputs = config.boot.kernelPackages.kernel.moduleBuildDependencies;

          buildPhase = ''
            make -C ${config.boot.kernelPackages.kernel.dev}/lib/modules/${modDirVersion}/build \
              M=$PWD/drivers/bluetooth modules
          '';

          installPhase = ''
            install -Dm644 drivers/bluetooth/btusb.ko \
              $out/lib/modules/${modDirVersion}/extra/btusb-mercusys.ko
          '';
        };
      in
      {
        boot.extraModulePackages = [ btusb-mercusys-ma530 ];

        systemd.services.btusb-mercusys-ma530 = {
          description = "Load patched btusb for Mercusys MA530";
          after = [ "systemd-modules-load.service" ];
          before = [ "bluetooth.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "load-patched-btusb" ''
              if ${pkgs.kmod}/bin/lsmod | ${pkgs.gnugrep}/bin/grep -q '^btusb'; then
                ${pkgs.kmod}/bin/rmmod btusb
              fi
              ${pkgs.kmod}/bin/insmod ${btusb-mercusys-ma530}/lib/modules/${modDirVersion}/extra/btusb-mercusys.ko
            '';
          };
        };
      };
  };
}
