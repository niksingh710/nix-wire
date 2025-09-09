{
  description = "A Nix wiring system to easily manage/wireup Nix configurations (flake-parts)";

  outputs = _: {
    mkFlake = import ./lib;
  };
}
