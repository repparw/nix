_: {
  den.aspects.mercusys-ma530 = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        inherit (config.boot.kernelPackages.kernel) modDirVersion;
        btusb-mercusys-ma530 = pkgs.stdenv.mkDerivation {
          pname = "btusb-mercusys-ma530";
          inherit (config.boot.kernelPackages.kernel) version;

          inherit (config.boot.kernelPackages.kernel) src;

          patches = [
            (pkgs.writeText "mercusys-ma530.patch" ''
              --- a/drivers/bluetooth/btusb.c
              +++ b/drivers/bluetooth/btusb.c
              @@ -812,6 +812,8 @@ static const struct usb_device_id quirks_table[] = {
              	{ USB_DEVICE(0x2ff8, 0xb011), .driver_info = BTUSB_REALTEK },

              	/* Additional Realtek 8761BUV Bluetooth devices */
              +	{ USB_DEVICE(0x2c4e, 0x0115), .driver_info = BTUSB_REALTEK |
              +					     BTUSB_WIDEBAND_SPEECH },
              	{ USB_DEVICE(0x2357, 0x0604), .driver_info = BTUSB_REALTEK |
              					     BTUSB_WIDEBAND_SPEECH },
            '')
          ];

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
              if ${lib.getExe' pkgs.kmod "lsmod"} | ${lib.getExe pkgs.gnugrep} -q '^btusb'; then
                ${lib.getExe' pkgs.kmod "rmmod"} btusb
              fi
              ${lib.getExe' pkgs.kmod "insmod"} ${btusb-mercusys-ma530}/lib/modules/${modDirVersion}/extra/btusb-mercusys.ko
            '';
          };
        };
      };
  };
}
