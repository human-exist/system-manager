{
  lib,

  nix,
  systemd,
  runCommand,
  makeBinaryWrapper,

  system-manager-unwrapped,
}:

runCommand "system-manager"
  {
    nativeBuildInputs = [ makeBinaryWrapper ];
    # The unwrapped version takes nix from the PATH, it will fail if nix
    # cannot be found.
    # The wrapped version has a reference to the nix store path, so nix is
    # part of its runtime closure.
    unwrapped = system-manager-unwrapped;
    meta.mainProgram = "system-manager";
  }
  ''
    # Wrap the CLI binary with nix in PATH
    makeWrapper \
      $unwrapped/bin/system-manager \
      $out/bin/system-manager \
      --prefix PATH : ${lib.makeBinPath [ nix ]}

    # Wrap the engine binary with nix (needed for register command) & systemd (systemd-tmpfiles for activation) in PATH
    makeWrapper \
      ${system-manager-unwrapped}/bin/system-manager-engine \
      $out/bin/system-manager-engine \
      --prefix PATH : ${lib.makeBinPath [ nix systemd ]}
  ''
