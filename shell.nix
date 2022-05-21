{ pkgs ? import <nixpkgs> { } }:

let
  version = "7.1.5";
  foundationdb-client = pkgs.stdenv.mkDerivation rec {
    name = "foundationdb-client";

    src = pkgs.fetchurl {
      url =
        "https://github.com/apple/foundationdb/releases/download/${version}/foundationdb-clients_${version}-1_amd64.deb";
      sha256 = "0isr5mslssii2fy8z2hhbzybqracd2n2ryvhvwm7y7zq8dz36k34";
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
    name = "foundationdb-server";

    src = pkgs.fetchurl {
      url =
        "https://github.com/apple/foundationdb/releases/download/${version}/foundationdb-server_${version}-1_amd64.deb";
      sha256 = "07j79xp4c8d2ym3dmh7pdk4wlprmkzbh9lp9cc6dgncxcm1zgv97";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.dpkg ];

    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      dpkg -x $src $out
      mv $out/usr/sbin $out/sbin
      mv $out/usr/lib $out/lib
    '';
  };
in pkgs.mkShell {
  nativeBuildInputs = [ foundationdb-client foundationdb-server ];
}
