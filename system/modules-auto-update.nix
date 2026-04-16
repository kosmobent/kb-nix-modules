{ config, lib, pkgs, ... }:

# =============================================================================
# auto-update.nix
#
# Periodically pulls the latest modules from a remote Git repo, replaces the
# local modules/ folder, rebuilds the NixOS system, and reboots.
#
# Configure this module from any other .nix file:
#
#   custom.system.modules-auto-update = {
#     enable         = true;
#     repoDomain     = "https://github.com/YOUR_USERNAME/YOUR_REPO.git";
#     repoBranch     = "main";       # optional, default: "main"
#     updateInterval = "hourly";     # optional, default: "hourly"
#     onBootDelay    = "5min";       # optional, default: "5min"
#   };
#
# Assumptions about your flake layout:
#   /etc/nixos/
#   ├── flake.nix          ← lives here, NOT in the repo
#   ├── flake.lock
#   └── modules/           ← contents are fully managed by this module
# =============================================================================

let
  cfg = config.custom.system.modules-auto-update;
in
{
  # ---------------------------------------------------------------------------
  # Option declarations
  # ---------------------------------------------------------------------------
  options.custom.system.modules-auto-update = {

    enable = lib.mkEnableOption "automatic NixOS config updates from Git";

    repoDomain = lib.mkOption {
      type        = lib.types.str;
      description = "Full URL of the Git repository to sync modules from.";
      example     = "https://github.com/YOUR_USERNAME/YOUR_REPO.git";
    };

    repoBranch = lib.mkOption {
      type        = lib.types.str;
      default     = "main";
      description = "Branch to track.";
    };

    flakeDir = lib.mkOption {
      type        = lib.types.str;
      default     = "/etc/nixos";
      description = "Absolute path to the flake root on this machine.";
    };

    updateInterval = lib.mkOption {
      type        = lib.types.str;
      default     = "hourly";
      description = ''
        Systemd calendar expression controlling how often to check for updates.
        Examples: "hourly", "daily", "*:0/30" (every 30 minutes).
      '';
    };

    onBootDelay = lib.mkOption {
      type        = lib.types.str;
      default     = "5min";
      description = "How long after boot to wait before the first update check.";
    };
  };

  # ---------------------------------------------------------------------------
  # Implementation (only active when enable = true)
  # ---------------------------------------------------------------------------
  config = lib.mkIf cfg.enable {

    systemd.tmpfiles.rules = [
      "d /var/lib/kb-nix-modules-auto-update 0700 root root -"
    ];

    systemd.services.kb-nix-modules-auto-update = {
      description = "NixOS automatic config update from Git";
      after       = [ "network-online.target" ];
      wants       = [ "network-online.target" ];

      serviceConfig = {
        Type            = "oneshot";
        User            = "root";
        TimeoutStartSec = "1800";
        StandardOutput  = "journal";
        StandardError   = "journal";
      };

      script =
        let
          modulesDir     = "${cfg.flakeDir}/modules";
          lastCommitFile = "/var/lib/kb-nix-modules-auto-update/last-commit";
        in
        ''
          set -euo pipefail

          REPO_URL="${cfg.repoDomain}"
          REPO_BRANCH="${cfg.repoBranch}"
          FLAKE_DIR="${cfg.flakeDir}"
          MODULES_DIR="${modulesDir}"
          LAST_COMMIT_FILE="${lastCommitFile}"
          WORK_DIR="$(${pkgs.coreutils}/bin/mktemp -d)"

          cleanup() { ${pkgs.coreutils}/bin/rm -rf "$WORK_DIR"; }
          trap cleanup EXIT

          echo "[kb-nix-modules-auto-update] Cloning $REPO_URL (branch: $REPO_BRANCH)..."
          ${pkgs.git}/bin/git clone \
            --depth 1 \
            --branch "$REPO_BRANCH" \
            "$REPO_URL" \
            "$WORK_DIR/repo"

          NEW_COMMIT="$(${pkgs.git}/bin/git -C "$WORK_DIR/repo" rev-parse HEAD)"
          echo "[kb-nix-modules-auto-update] Remote HEAD is $NEW_COMMIT"

          LAST_COMMIT=""
          if [ -f "$LAST_COMMIT_FILE" ]; then
            LAST_COMMIT="$(${pkgs.coreutils}/bin/cat "$LAST_COMMIT_FILE")"
          fi

          if [ "$NEW_COMMIT" = "$LAST_COMMIT" ]; then
            echo "[kb-nix-modules-auto-update] Already up-to-date ($NEW_COMMIT). Nothing to do."
            exit 0
          fi

          echo "[kb-nix-modules-auto-update] Changes detected ($LAST_COMMIT -> $NEW_COMMIT). Syncing modules..."

          ${pkgs.rsync}/bin/rsync \
            --archive \
            --delete \
            --exclude=".git" \
            "$WORK_DIR/repo/" \
            "$MODULES_DIR/"

          echo "[kb-nix-modules-auto-update] Sync complete. Running nixos-rebuild switch..."

          ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
            --flake "$FLAKE_DIR#$(${pkgs.hostname}/bin/hostname)" 2>&1

          echo "$NEW_COMMIT" > "$LAST_COMMIT_FILE"

          echo "[kb-nix-modules-auto-update] Rebuild successful. Rebooting..."
          ${pkgs.systemd}/bin/systemctl reboot
        '';
    };

    systemd.timers.kb-nix-modules-auto-update = {
      description = "NixOS automatic config update timer";
      wantedBy    = [ "timers.target" ];
      timerConfig = {
        OnCalendar         = cfg.updateInterval;
        OnBootSec          = cfg.onBootDelay;
        Persistent         = true;
        RandomizedDelaySec = "3min";
        Unit               = "kb-nix-modules-auto-update.service";
      };
    };
  };
}