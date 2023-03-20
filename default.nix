{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.pup
    pkgs.xmlstarlet
    # find a package to put in place of motivate
  ];
}
