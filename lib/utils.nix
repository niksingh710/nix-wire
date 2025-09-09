{ inputs, lib ? import <nixpkgs/lib>, ... }:

let
  # Remove the ".nix" suffix from a filename
  stripNix = name: lib.removeSuffix ".nix" name;

  # Check if an entry is a regular .nix file
  isNixFile = name: type:
    type == "regular" && lib.hasSuffix ".nix" name;

  # Check if an entry is a directory containing default.nix
  isDirWithDefault = name: type: dir:
    type == "directory" && builtins.pathExists (dir + "/${name}/default.nix");

  # Read a directory safely; return empty set if it does not exist
  files = dir:
    if builtins.pathExists dir
    then builtins.readDir dir
    else { };

  commonNix = {
    nixpkgs = {
      config.allowUnfree = lib.mkDefault true;
      overlays = lib.attrValues inputs.self.overlays;
    };
    nix = {
      settings = {
        max-jobs = lib.mkDefault "auto";
        experimental-features = lib.mkDefault "nix-command flakes";
      };
    };
  };

  # Filter out foo.nix if foo/default.nix exists
  filterPreferDir = dir: fs:
    lib.filterAttrs
      (name: type:
        !(lib.hasSuffix ".nix" name
          && fs ? ${lib.removeSuffix ".nix" name}
          && isDirWithDefault (lib.removeSuffix ".nix" name) (fs.${lib.removeSuffix ".nix" name}) dir)
      )
      fs;

  commonSpecialArgs = { inherit inputs; flake = inputs.self; };

  # Extract common home-manager modules for nixos/darwin hosts
  #
  # Parameters:
  #   - type: "nixos" | "darwin"
  #   - dir: host config base directory
  #   - hostname: name of the host
  commonHomeModules = type: dir: hostname:
    let
      hmInput =
        inputs.home-manager
          or (throw "nix-wire uses home-manager but it is not available in inputs");

      hmImport =
        if type == "nixos" then
          hmInput.nixosModules.home-manager
        else
          hmInput.darwinModules.home-manager;
    in
    [
      hmImport
      ({ pkgs, ... }: {
        home-manager.useGlobalPkgs = lib.mkDefault true;
        home-manager.useUserPackages = lib.mkDefault true;
        home-manager.backupFileExtension = lib.mkDefault "";
        home-manager.extraSpecialArgs = commonSpecialArgs;
        home-manager.users = getUsersHome dir hostname;
        home-manager.sharedModules = [
          {
            home.sessionPath = lib.mkIf pkgs.stdenv.isDarwin [
              "/etc/profiles/per-user/$USER/bin" # To access home-manager binaries
              "/nix/var/nix/profiles/system/sw/bin" # To access nix-darwin binaries
              "/usr/local/bin" # Some macOS GUI programs install here
            ];
          }
        ];
      })
    ];

  # Build common modules for nixos/darwin hosts
  #
  # Parameters:
  #   - type: "nixos" | "darwin"
  #   - home: boolean, whether to include home-manager modules
  #   - path: path to the host's config file
  #   - dir: base directory for the host configs
  #   - hostname: name of the host
  commonModules = type: home: path: dir: hostname:
    let
      homeModules =
        if home then
          commonHomeModules type dir hostname
        else
          [ ];
    in
    [
      path
      ({ pkgs, ... }: {
        imports = homeModules;
        users.users = getUsers dir hostname pkgs;
      })
      commonNix
    ];

  # ------------------------------------------------------------------------
  # Generic walker function
  #
  # wireGeneric scans a given directory and collects all `.nix` files and
  # subdirectories containing a `default.nix` file into an attribute set.
  #
  # Precedence rule:
  #   - If both `foo.nix` and `foo/default.nix` exist, `foo/default.nix` is used.
  #   - Otherwise, whichever exists is used.
  #
  # Parameters:
  #   - dir: the directory to scan
  #   - buildFn: a function applied to each file or default.nix directory.
  #              Receives two arguments:
  #                1. path: full path to the file or default.nix
  #                2. name: the entry name (filename without .nix or directory name)
  #
  # Returns:
  #   - An attrset mapping:
  #       { name = buildFn(path, name); … }
  #
  # Example usage:
  #   wireGeneric {
  #     dir = ./packages;
  #     buildFn = path: name: pkgs.callPackage path {};
  #   }
  #
  # This modification allows buildFn to be aware of the specific entry it is
  # processing, e.g., hostnames, usernames, or package names.
  # ------------------------------------------------------------------------
  wireGeneric = { dir, buildFn }:
    let fs = filterPreferDir dir (files dir); in
    lib.foldlAttrs
      (acc: name: type:
        if isDirWithDefault name type dir then
          acc // { ${name} = buildFn (dir + "/" + name) name; }
        else if isNixFile name type then
          acc // { ${stripNix name} = buildFn (dir + "/" + name) (stripNix name); }
        else acc
      )
      { }
      fs;

  # ------------------------------------------------------------------------
  # wirePackages: Collect .nix files or dirs with default.nix from a packages
  # directory and call pkgs.callPackage on them
  # ------------------------------------------------------------------------
  wirePackages = { pkgs, dir, callFn ? pkgs.callPackage }:
    wireGeneric {
      inherit dir;
      buildFn = path: name: callFn path { };
    };

  # ------------------------------------------------------------------------
  # mkUsers: Generic user collector
  #
  # Parameters:
  #   - hostDir: base directory (e.g., ./darwin)
  #   - hostname: name of the host (e.g., macbook)
  #   - userBuildFn: function (path: username: value)
  #
  # Returns:
  #   { username = userBuildFn path username; … }
  # ------------------------------------------------------------------------
  mkUsers = hostDir: hostname: userBuildFn:
    let
      usersDir = hostDir + "/" + hostname + "/users";
    in
    wireGeneric {
      dir = usersDir;
      buildFn = path: username: userBuildFn path username;
    };

  # ------------------------------------------------------------------------
  # Specializations
  # ------------------------------------------------------------------------

  # Create user home directory configurations
  getUsers = hostDir: hostname: pkgs:
    mkUsers hostDir hostname (_path: username: {
      home = lib.mkDefault
        "/${if pkgs.stdenv.isDarwin then "Users" else "home"}/${username}";
    });

  # Create Home Manager user configurations
  getUsersHome = hostDir: hostname:
    mkUsers hostDir hostname (path: _username: {
      imports = [ path ];
    });

  # ------------------------------------------------------------------------
  # wireModules: Collect modules from a directory
  # Uses wireGeneric and returns an attrset mapping each modulename to its path
  # ------------------------------------------------------------------------
  wireModules = { dir }:
    wireGeneric {
      inherit dir;
      buildFn = path: name: path;
    };


  # ------------------------------------------------------------------------
  # wireOverlays: Collect overlays from a overlays directory
  # imports each overlay with inputs and flake = inputs.self
  # ------------------------------------------------------------------------
  wireOverlays = { dir }:
    wireGeneric {
      inherit dir;
      buildFn = path: name: import path commonSpecialArgs;
    };

  # ------------------------------------------------------------------------
  # mkDarwinConfigs: Collect Darwin host configurations
  # Uses wireGeneric and wraps each config with nix-darwin.lib.darwinSystem
  # ------------------------------------------------------------------------
  mkDarwinConfigs = { dir, home }:
    let
      nix-darwin = inputs.nix-darwin
        or (throw "nix-wire uses nix-darwin but it is not available in inputs");
    in
    wireGeneric {
      inherit dir;
      buildFn = path: name: nix-darwin.lib.darwinSystem {
        specialArgs = commonSpecialArgs;
        modules = (commonModules "darwin" home path dir name) ++ [
          {
            networking.hostName = lib.mkDefault name;
          }
        ];
      };
    };

  # ------------------------------------------------------------------------
  # mkNixosConfigs: Collect NixOS host configurations
  # Uses wireGeneric and wraps each config with nixpkgs.lib.nixosSystem
  # ------------------------------------------------------------------------
  mkNixosConfigs = { dir, home }:
    wireGeneric {
      inherit dir;
      buildFn = path: name: inputs.nixpkgs.lib.nixosSystem {
        specialArgs = commonSpecialArgs;
        modules = (commonModules "nixos" home path dir name) ++ [
          { networking.hostName = lib.mkDefault name; }
        ];
      };
    };

  # ------------------------------------------------------------------------
  # mkHomeConfigs: Collect Home Manager user configurations
  # Uses wireGeneric and wraps each config with home-manager.lib.homeManagerConfiguration
  #
  # Parameters:
  #   - dir: directory containing user configuration files
  #   - pkgs: nixpkgs instance used for homeDirectory path resolution
  # ------------------------------------------------------------------------
  mkHomeConfigs = { dir, pkgs }:
    let
      hmInput =
        inputs.home-manager
          or (throw "nix-wire uses home-manager but it is not available in inputs");
    in
    wireGeneric {
      inherit dir;
      buildFn = path: username:
        hmInput.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs; flake = inputs.self; };
          modules = [
            path
            {
              home = {
                username = username;
                homeDirectory = "/${if pkgs.stdenv.isDarwin then "Users" else "home"}/${username}";
              };
              nix.package = lib.mkDefault pkgs.nix;
            }
            commonNix
          ];
        };
    };

in
{
  inherit wirePackages mkDarwinConfigs mkNixosConfigs mkHomeConfigs wireModules wireOverlays;
}
