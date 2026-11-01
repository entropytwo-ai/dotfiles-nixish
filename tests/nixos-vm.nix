# Boots a real NixOS VM with the dotfiles-nixish module and checks, as a normal
# user, that every tool RUNS (with its data) and the shell config works.
# Run (needs KVM):   nix build -L .#checks.x86_64-linux.nixos-module
{ pkgs, module }:
pkgs.testers.runNixOSTest {
  name = "dotfiles-nixish-module";

  nodes.machine = { ... }: {
    imports = [ module ];
    programs.dotfiles-nixish = { enable = true; shellConfig = true; };
    programs.zsh.enable = true;
    users.users.alice = { isNormalUser = true; extraGroups = [ "wheel" ]; };
    i18n.defaultLocale = "en_US.UTF-8";
    virtualisation.memorySize = 2048;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    def as_alice(cmd, shell="bash"):
        # interactive shell in a login session, like opening a terminal;
        # only what follows the marker (the greeting comes first)
        out = machine.succeed(
            f"su - alice -c \"TERM=dumb {shell} -ic 'echo __CI_OUT__; {cmd}'\" </dev/null 2>&1"
        )
        return out.split("__CI_OUT__", 1)[1]

    # every tool runs (fortune must have its quotes, not just the binary)
    for t in ["eza", "duf", "nmap", "ncdu", "btop", "fzf", "glances", "bat", "fastfetch"]:
        as_alice(f"{t} --version >/dev/null")
    assert "moo" in as_alice("cowsay moo")
    q = as_alice("fortune")
    assert q.strip() and "No fortunes" not in q, f"fortune: {q!r}"

    # xtree from the module's package
    assert "Name" in as_alice("xtree -L 1 /etc")
    assert "Name" in as_alice("xtree -p -u -t -L 1 /etc")

    # shell config applied system-wide (shellConfig = true)
    t = as_alice("type l")
    assert "eza" in t, f"type l: {t!r}"
    assert "alias" in as_alice("type cowsays")
    assert "eza" in as_alice("alias l", shell="zsh")
    greet = machine.succeed("su - alice -c 'TERM=dumb bash -ic true' </dev/null 2>&1")
    for bad in ["command not found", "No fortunes", "syntax error"]:
        assert bad not in greet, f"greeting prints {bad!r}:\n{greet}"
    assert "LANG=en_US.UTF-8" in as_alice("echo LANG=$LANG")
  '';
}
