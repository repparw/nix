{inputs, config, lib, pkgs, ...}: {
  system.autoUpgrade = {
    enable = true;
    flake = "github:repparw/nix";
    dates = "02:00";
  };

  # Add Git-aware upgrade service
  systemd.services.nixos-upgrade = {
    path = with pkgs; [ systemd libnotify git ];
    
    # Pre-upgrade hook to check Git state
    preStart = pkgs.writeScript "pre-upgrade-check" ''
      #!${pkgs.bash}/bin/bash
      set -e

      # Check if there are uncommitted changes
      if ! git diff --quiet; then
        echo "Warning: There are uncommitted changes in the configuration"
        echo "The upgrade will use these changes but they won't be committed"
      fi

      # Check if we're behind the remote
      if git fetch origin && ! git diff --quiet origin/$(git branch --show-current); then
        echo "Warning: Local configuration is behind remote"
        echo "Consider pulling changes before upgrade"
      fi
    '';

    # Post-upgrade hook to handle Git state
    postStart = pkgs.writeScript "post-upgrade-handler" ''
      #!${pkgs.bash}/bin/bash
      set -e

      # Wait for upgrade to complete
      sleep 5

      # Get the current generation number
      CURRENT_GEN=$(nix-env --list-generations | grep current | awk '{print $1}')

      # Create a commit message with generation info
      COMMIT_MSG="Auto-upgrade to generation $CURRENT_GEN"

      # Check if there are changes to commit
      if git diff --quiet; then
        echo "No changes to commit"
      else
        # Stage all changes
        git add .
        
        # Create a commit
        if git commit -m "$COMMIT_MSG"; then
          echo "Changes committed successfully"
        else
          echo "No changes to commit or commit failed"
        fi
      fi

      # Send notification
      for user in $(loginctl list-users | awk 'NR>1 {print $2}'); do
        if [ -n "$user" ]; then
          DISPLAY=:0 sudo -u "$user" notify-send \
            -a "NixOS Updates" \
            -u "normal" \
            "System Updated" \
            "System has been successfully updated to generation $CURRENT_GEN"
          break
        fi
      done
    '';

    onFailure = pkgs.writeScript "upgrade-failure-notification" ''
      #!${pkgs.bash}/bin/bash
      set -e

      for user in $(loginctl list-users | awk 'NR>1 {print $2}'); do
        if [ -n "$user" ]; then
          DISPLAY=:0 sudo -u "$user" notify-send \
            -a "NixOS Updates" \
            -u "critical" \
            "Update Failed" \
            "System update failed. Check journalctl for details."
          break
        fi
      done
    '';
  };
}