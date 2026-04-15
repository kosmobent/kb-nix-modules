{ config, lib, pkgs, ... }:

{
  options.custom.require.newt = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Require newt service (alias for custom.newt.enable)";
  };

  options.custom.newt = {

    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable newt service ";
    };

    id = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "ID for newt service";
    };

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Domain for newt service";
    };

  };

  config = lib.mkIf (config.custom.require.newt || config.custom.newt.enable) {
    assertions = [
      {
        assertion = config.custom.newt.id != null && config.custom.newt.id != "";
        message = "newt was enabled without proper setup! Define a value for custom.newt.id";
      }

      {
        assertion = config.custom.newt.domain != null && config.custom.newt.domain != "";
        message = "newt was enabled without proper setup! Define a value for custom.newt.domain";
      }
    ];

    services.newt = {
      enable = true;
      settings = {
        endpoint = config.custom.newt.domain;
        id = config.custom.newt.id;
      };
      environmentFile = "/etc/nixos/keys/newt.environment";
    };
  };

}