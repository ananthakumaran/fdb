{ pkgs ? import <nixpkgs> { } }:

let
  version = "6.3.23";
  foundationdb-client = pkgs.stdenv.mkDerivation rec {
    name = "foundationdb-client";

    src = pkgs.fetchurl {
      url =
        "https://github.com/apple/foundationdb/releases/download/${version}/foundationdb-clients_${version}-1_amd64.deb";
      sha256 = "0dvy61ci2w54zviqsqi5s9r0ymfg9jrz21pr8fabldhvz1k4sn3i";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.dpkg ];

    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      dpkg -x $src $out
      mv $out/usr/bin $out/bin
      mv $out/usr/include $out/include
      mv $out/usr/lib $out/lib
    '';
  };

  foundationdb-server = pkgs.stdenv.mkDerivation rec {
    name = "foundationdb-client";

    src = pkgs.fetchurl {
      url =
        "https://github.com/apple/foundationdb/releases/download/${version}/foundationdb-server_${version}-1_amd64.deb";
      sha256 = "0jxd9xcfaxaa5gp0y6mbwr827kzyal06pk4jdd25sni5adl3cxh6";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.dpkg pkgs.tree ];

    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      dpkg -x $src $out
      mv $out/usr/sbin $out/sbin
      mv $out/usr/lib $out/lib
    '';
  };
in (pkgs.buildFHSUserEnv {
  name = "fdb";
  targetPkgs = pkgs: ([ foundationdb-client foundationdb-server ]);
  runScript = "zsh";
}).env
