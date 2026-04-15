{ config, lib, pkgs, ... }:

{
  options.custom.require.docker = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Require docker service (alias for custom.docker.enable)";
  };

  options.custom.docker = {

    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable docker service ";
    };

  };

  config = lib.mkIf (config.custom.require.docker || config.custom.docker.enable) {
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
  };

}