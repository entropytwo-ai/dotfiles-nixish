# The dotfiles-nixish package set as nixpkgs attributes (used by module.nix,
# default.nix and flake.nix). It is READ FROM ../packages/package_list.txt -
# the same list install.sh uses on every OS - so add packages there, not here.
#
# Taken from the list: the [prerequisites] and [tools] sections (plus any
# extra section names passed in `sections`). Per line the nix= name is used if
# given, else the package name:  a,b = first one that exists in nixpkgs,
# a+b = both, - = skip. Names that don't exist in nixpkgs are skipped with a
# warning (evaluation trace) instead of failing the build. Dotted names such as
# python3Packages.rich work too.
pkgs:
{ sections ? [ "prerequisites" "tools" ], listFile ? ../packages/package_list.txt }:
let
  inherit (pkgs) lib;

  # "  foo  nix=a,b   # comment\r" -> [ "foo" "nix=a,b" ]
  tokens = line:
    let noComment = builtins.head (lib.splitString "#" (lib.replaceStrings [ "\r" ] [ "" ] line));
    in builtins.filter (t: builtins.isString t && t != "") (builtins.split "[ \t]+" noComment);

  # fold over the lines, remembering the current [section]
  parsed = builtins.foldl'
    (st: line:
      let
        toks = tokens line;
        hdr = if toks == [ ] then null else builtins.match "[[]([A-Za-z0-9_-]+)[]]" (builtins.head toks);
      in
      if toks == [ ] then st
      else if hdr != null then st // { sec = builtins.head hdr; }
      else st // { entries = st.entries ++ [{ inherit (st) sec; name = builtins.head toks; opts = builtins.tail toks; }]; })
    { sec = "tools"; entries = [ ]; }
    (lib.splitString "\n" (builtins.readFile listFile));

  # value of key=... on the line, or null
  opt = key: e:
    let hits = builtins.filter (t: lib.hasPrefix "${key}=" t) e.opts;
    in if hits == [ ] then null else lib.removePrefix "${key}=" (lib.last hits);

  exists = attr: lib.hasAttrByPath (lib.splitString "." attr) pkgs;
  get = attr: lib.getAttrFromPath (lib.splitString "." attr) pkgs;

  resolve = e:
    let
      spec = let v = opt "nix" e; in if v == null then e.name else v;
      alts = map (lib.splitString "+") (lib.splitString "," spec);
      found = lib.findFirst (parts: builtins.all exists parts) null alts;
    in
    if spec == "-" then [ ]
    else if found == null then
      builtins.trace "dotfiles-nixish: package_list.txt: '${e.name}' (nix name: ${spec}) is not in nixpkgs - skipped" [ ]
    else map get found;

  wanted = builtins.filter (e: builtins.elem e.sec sections) parsed.entries;
in
lib.unique (lib.concatMap resolve wanted)
