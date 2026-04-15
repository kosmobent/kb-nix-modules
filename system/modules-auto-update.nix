{ config, lib, pkgs, ... }:

# =============================================================================
# auto-update.nix
#
# Periodically pulls the latest modules from a remote Git repo, replaces the
# local modules/ folder, rebuilds the NixOS system, and reboots.
#
# Assumptions about your flake layout:
#   /etc/nixos/
#   ├── flake.nix          ← lives here, NOT in the repo
#   ├── flake.lock
#   └── modules/           ← contents are fully managed by this module
#
# The remote repo is expected to contain only the files that belong inside
# the modules/ folder (i.e. the repo root == modules/).
# =============================================================================

let
  # ---------------------------------------------------------------------------
  # USER CONFIG — adjust these variables to match your setup
  # ---------------------------------------------------------------------------

  # Full HTTPS URL of the repository (no SSH, so no key management needed).
  repoUrl = "https://github.com/YOUR_USERNAME/YOUR_REPO.git";

  # Branch to track.
  repoBranch = "main";

  # Absolute path to the flake root on this machine.
  flakeDir = "/etc/nixos";

  # Absolute path to the modules folder that will be synced.
  modulesDir = "${flakeDir}/modules";

  # How often to check for updates (systemd calendar expression).
  # "hourly"  → every hour
  # "*:0/30"  → every 30 minutes
  # "daily"   → once a day at midnight
  updateInterval = "hourly";

  # Path to a file that stores the last-seen commit hash.
  # This prevents unnecessary rebuilds when nothing changed.
  lastCommitFile = "/var/lib/nixos-auto-update/last-commit";

  # ---------------------------------------------------------------------------
in
{
  # A small state directory for tracking the last commit
  systemd.tmpfiles.rules = [
    "d /var/lib/nixos-auto-update 0700 root root -"
  ];

  # ---------------------------------------------------------------------------
  # The update script
  # ---------------------------------------------------------------------------
  systemd.services.nixos-auto-update = {
    description = "NixOS automatic config update from Git";

    # Don't run during early boot — wait for the network
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];

    # Never run more than one instance at a time
    serviceConfig = {
      Type            = "oneshot";
      User            = "root";
      # Give the rebuild plenty of time (30 min)
      TimeoutStartSec = "1800";
      # Keep logs for easier debugging
      StandardOutput  = "journal";
      StandardError   = "journal";
    };

    script = ''
      set -euo pipefail

      REPO_URL="${repoUrl}"
      REPO_BRANCH="${repoBranch}"
      FLAKE_DIR="${flakeDir}"
      MODULES_DIR="${modulesDir}"
      LAST_COMMIT_FILE="${lastCommitFile}"
      WORK_DIR="$(${pkgs.coreutils}/bin/mktemp -d)"

      cleanup() { ${pkgs.coreutils}/bin/rm -rf "$WORK_DIR"; }
      trap cleanup EXIT

      echo "[auto-update] Cloning $REPO_URL (branch: $REPO_BRANCH)..."
      ${pkgs.git}/bin/git clone \
        --depth 1 \
        --branch "$REPO_BRANCH" \
        "$REPO_URL" \
        "$WORK_DIR/repo"

      NEW_COMMIT="$(${pkgs.git}/bin/git -C "$WORK_DIR/repo" rev-parse HEAD)"
      echo "[auto-update] Remote HEAD is $NEW_COMMIT"

      # Read the last applied commit (empty string if file doesn't exist yet)
      LAST_COMMIT=""
      if [ -f "$LAST_COMMIT_FILE" ]; then
        LAST_COMMIT="$(${pkgs.coreutils}/bin/cat "$LAST_COMMIT_FILE")"
      fi

      if [ "$NEW_COMMIT" = "$LAST_COMMIT" ]; then
        echo "[auto-update] Already up-to-date ($NEW_COMMIT). Nothing to do."
        exit 0
      fi

      echo "[auto-update] Changes detected ($LAST_COMMIT -> $NEW_COMMIT). Syncing modules..."

      # Sync repo contents → modules/ directory.
      # --delete removes files that are no longer in the repo.
      # The trailing slash on the source is intentional (rsync semantics).
      ${pkgs.rsync}/bin/rsync \
        --archive \
        --delete \
        --exclude=".git" \
        "$WORK_DIR/repo/" \
        "$MODULES_DIR/"

      echo "[auto-update] Sync complete. Running nixos-rebuild switch..."

      # Rebuild. Use --flake pointing at the flake root.
      ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
        --flake "$FLAKE_DIR#$(${pkgs.hostname}/bin/hostname)" 2>&1

      # Persist the new commit hash only after a successful rebuild
      echo "$NEW_COMMIT" > "$LAST_COMMIT_FILE"

      echo "[auto-update] Rebuild successful. Rebooting..."
      ${pkgs.systemd}/bin/systemctl reboot
    '';
  };

  # ---------------------------------------------------------------------------
  # Timer — triggers the service on the configured schedule
  # ---------------------------------------------------------------------------
  systemd.timers.nixos-auto-update = {
    description  = "NixOS automatic config update timer";
    wantedBy     = [ "timers.target" ];
    timerConfig  = {
      OnCalendar         = updateInterval;
      # Also run shortly after boot in case the machine was off during a
      # scheduled window
      OnBootSec          = "5min";
      # If a run was missed (e.g. machine was off), run it once on next boot
      Persistent         = true;
      RandomizedDelaySec = "3min";
      Unit               = "nixos-auto-update.service";
    };
  };
}