{ config, lib, pkgs, ... }:

# "Hello World!" says the cloud... 

{
  imports = [
    ./hostname.nix
    ./modules-auto-update.nix
  ];
}
