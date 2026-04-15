# modules/modules-auto-update.nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.custom.system.modules-auto-update;
  git = "${pkgs.git}/bin/git";  # Add this line
  updateScript = pkgs.writeShellScript "kb-nix-modules-auto-update" ''
    set -e
    
    echo "[$(date)] Starting NixOS modules-auto-update..."
    
    # Define paths
    REPO_URL="${cfg.repositoryUrl}"
    MODULES_DIR="/etc/nixos/modules"
    TEMP_DIR=$(mktemp -d)
    
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Clone or update the repository
    echo "[$(date)] Cloning/updateing repository..."
    if [ -d "$TEMP_DIR/repo" ]; then
      cd "$TEMP_DIR/repo"
      ${git} pull origin ${cfg.branch}
    else
      ${git} clone --branch ${cfg.branch} "$REPO_URL" "$TEMP_DIR/repo"
    fi
    
    # Sync modules folder
    echo "[$(date)] Syncing modules folder..."
    rm -rf "$MODULES_DIR"
    cp -r "$TEMP_DIR/repo/modules" "$MODULES_DIR"
    
    # Check if changes were made
    cd /etc/nixos/
    if ! ${git} diff --quiet; then
      echo "[$(date)] Changes detected, rebuilding system..."
      
      nixos-rebuild switch --flake .#nixos
      
      ${lib.optionalString cfg.autoReboot ''
        echo "[$(date)] Rebooting system..."
        shutdown -r +1 "NixOS modules-auto-update: rebooting in 1 minute"
      ''}
    else
      echo "[$(date)] No changes detected, skipping rebuild."
    fi
    
    echo "[$(date)] modules-auto-update completed."
  '';
in
{
  options.custom.system.modules-auto-update = {
    enable = mkEnableOption "NixOS automatic configuration updates";
    
    repositoryUrl = mkOption {
      type = types.str;
      description = "Git repository URL containing the modules folder";
      example = "https://github.com/user/nixos-modules.git";
    };
    
    branch = mkOption {
      type = types.str;
      description = "Git branch to pull from";
      default = "main";
    };
    
    updateInterval = mkOption {
      type = types.str;
      description = "Systemd timer interval (e.g., 'hourly', '*-*-* 02:00:00')";
      default = "daily";
    };
    
    autoReboot = mkEnableOption "automatic reboot after updates" // { default = false; };    
  };
  
  config = mkIf cfg.enable {
    systemd.services.kb-nix-modules-auto-update = {
      description = "NixOS automatic configuration update";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = updateScript;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
    
    systemd.timers.kb-nix-modules-auto-update = {
      description = "NixOS automatic configuration update timer";
      timerConfig = {
        OnCalendar = cfg.updateInterval;
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
