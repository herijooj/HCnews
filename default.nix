{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.pup
    pkgs.xmlstarlet
    pkgs.jq
    pkgs.bc
    pkgs.python3
  ];
}
