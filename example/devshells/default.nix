{ pkgs, ... }:
pkgs.mkShell {
  shellHook = ''
    echo "Welcome to the development shell!"
  '';
}
