{
  description = "lapNAS: the basement laptop home server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only for packages that must be newer than 26.05 has (see media.nix: Seerr).
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      host =
        path:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            disko.nixosModules.disko
            path
          ];
        };
    in
    {
      nixosConfigurations = {
        # The real laptop.
        lapnas = host ./hosts/lapnas;
        # The same config in a VirtualBox VM on the PC (docs/vm.md).
        lapnas-vm = host ./hosts/lapnas-vm;
        # USB installer with sshd and the PC's key (docs/install.md).
        installer = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./installer ];
        };
      };

      packages.${system}.installer-iso = self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
