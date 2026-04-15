{ config, lib, pkgs, ... }:

{
  options.custom.system = {

    deviceName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "alias for networking.hostName";
    };

  };

  config = lib.mkIf (config.custom.require.newt || config.custom.newt.enable) {
    assertions = [
      {
        assertion = config.custom.system.deviceName != null && config.custom.system.deviceName != "";
        message = "A device name (aka. hostName) must be set! Define it using custom.system.deviceName";
      }
    ];

    networking.hostName = config.custom.system.deviceName;
  };

}