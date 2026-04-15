{ config, lib, pkgs, ... }:

{
  options.custom.require.nextcloud = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Require nextcloud service (alias for custom.nextcloud.enable)";
  };

  options.custom.nextcloud = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable nextcloud service";
    };
  };

  config = lib.mkIf (config.custom.require.nextcloud || config.custom.nextcloud.enable) {
    custom.require = {
      docker = true;
      newt = true;
    }; 
    
    systemd.tmpfiles.rules = [
      "d /mnt/nextcloud-data 0750 root root -"
    ];

    systemd.services.NetworkManager-wait-online.enable = false;

    systemd.services."docker-nextcloud-aio-mastercontainer" = {
      after    = [ "docker.service" "network.target" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        ExecStartPre = [
          "+${pkgs.writeShellScript "wait-for-network" ''
            echo "Waiting for network connectivity..."
            until ${pkgs.curl}/bin/curl -s --max-time 5 https://ghcr.io > /dev/null 2>&1; do
              echo "Network not ready, retrying in 5 seconds..."
              sleep 5
            done
            echo "Network is ready."
          ''}"
        ];
        TimeoutStartSec = lib.mkForce "300";
      };
    };

    virtualisation.oci-containers = {
      backend = "docker";
      containers."nextcloud-aio-mastercontainer" = {
        image = "ghcr.io/nextcloud-releases/all-in-one:latest";
        extraOptions = [ "--init" ];
        ports = [
          "8080:8080"
        ];
        volumes = [
          "nextcloud_aio_mastercontainer:/mnt/docker-aio-config"
          "/var/run/docker.sock:/var/run/docker.sock:ro"
        ];
        environment = {
          APACHE_PORT            = "11000";
          APACHE_IP_BINDING      = "127.0.0.1";
          SKIP_DOMAIN_VALIDATION = "true";
          NEXTCLOUD_DATADIR      = "/mnt/nextcloud-data";
          TALK_PORT              = "3478";
        };
      };
    };
  };
}