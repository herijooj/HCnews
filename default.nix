{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.pup
    pkgs.xmlstarlet
    pkgs.jq
    pkgs.python3
    pkgs.python311Packages.python-telegram-bot
    pkgs.python311Packages.schedule
    pkgs.python311Packages.httpx
  ];
}
