# xtree packaged for Nix (shebang patched to the Nix store bash).
{ stdenvNoCC, bash }:
stdenvNoCC.mkDerivation {
  pname = "xtree";
  version = "1.0";
  src = ../scripts/xtree.sh;
  dontUnpack = true;
  buildInputs = [ bash ];
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/xtree
    runHook postInstall
  '';
  meta.mainProgram = "xtree";
}
