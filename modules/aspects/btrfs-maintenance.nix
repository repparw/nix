{ den, ... }:
{
  den.aspects.btrfs-maintenance = {
    nixos =
      { pkgs, ... }:
      let
        root = "/";
        hdd = "/mnt/hdd";
        minUnallocatedGiB = 10;
        metadataCriticalPercent = 97;
        globalReserveMaxConsecutive = 3;
      in
      {
        fileSystems.${root}.options = [
          "subvol=@"
          "noatime"
          "compress=zstd"
          "discard=async"
        ];

        services.btrfs.autoScrub = {
          enable = true;
          fileSystems = [
            root
            hdd
          ];
          interval = "monthly";
        };

        systemd.services.btrfs-balance-root = {
          description = "Light btrfs balance on root";
          documentation = [ "man:btrfs-balance(8)" ];
          serviceConfig = {
            Type = "oneshot";
            IOSchedulingClass = "idle";
          };
          script = ''
            ${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=20 -musage=50 ${root}
          '';
        };

        systemd.timers.btrfs-balance-root = {
          description = "Monthly light btrfs balance on root";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "monthly";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
        };

        systemd.services.btrfs-health-root = {
          description = "Check root btrfs allocation health";
          documentation = [ "man:btrfs-filesystem(8)" ];
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "btrfs-health-root";
          };
          path = with pkgs; [
            btrfs-progs
            coreutils
            gawk
            gnugrep
            gnused
          ];
          script = ''
            set -eu

            usage="$(btrfs filesystem usage ${root})"

            unallocated_gib="$(
              printf '%s\n' "$usage" |
                awk '/Unallocated:/ { getline; print $NF }' |
                sed 's/GiB$//'
            )"
            metadata_pct="$(
              printf '%s\n' "$usage" |
                awk '/Metadata,DUP:/ {
                  sub(/^.*\(/, "", $0)
                  sub(/%\).*$/, "", $0)
                  print $0
                }'
            )"
            global_reserve_used="$(
              printf '%s\n' "$usage" |
                awk '/Global reserve:/ { print $NF }'
            )"

            failed=0

            if awk "BEGIN { exit !($unallocated_gib < ${toString minUnallocatedGiB}) }"; then
              echo "root btrfs unallocated space is low: ''${unallocated_gib} GiB < ${toString minUnallocatedGiB} GiB"
              failed=1
            fi

            if awk "BEGIN { exit !($metadata_pct >= ${toString metadataCriticalPercent}) }"; then
              echo "root btrfs metadata allocation is high: ''${metadata_pct}% >= ${toString metadataCriticalPercent}%"
              failed=1
            fi

            reserve_count_file="$STATE_DIRECTORY/global-reserve-count"
            if [ "$global_reserve_used" = "0.00B" ]; then
              printf '0\n' > "$reserve_count_file"
            else
              count=0
              [ -f "$reserve_count_file" ] && count="$(cat "$reserve_count_file")"
              count="$((count + 1))"
              printf '%s\n' "$count" > "$reserve_count_file"

              if [ "$count" -ge ${toString globalReserveMaxConsecutive} ]; then
                echo "root btrfs global reserve has been in use for $count consecutive checks: $global_reserve_used"
                failed=1
              else
                echo "root btrfs global reserve is currently in use: $global_reserve_used ($count/${toString globalReserveMaxConsecutive})"
              fi
            fi

            exit "$failed"
          '';
        };

        systemd.timers.btrfs-health-root = {
          description = "Daily root btrfs allocation health check";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "30m";
          };
        };
      };
  };
}
