{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.system-manager.selinux;
  # Gets the systemd unit files that will need their selinux context changed
  unitDir =
    let
      enabledUnits = lib.filterAttrs (_: unit: unit.enable) config.systemd.units;
      unitValues = lib.attrValues enabledUnits;
      unitOutPaths = builtins.map (unit: unit.unit) unitValues;
    in
    lib.unique unitOutPaths;

  # Nixpkgs' selinux-python omits the `audit` module from its pythonPath, but
  # seobject.py needs it for fcontext auditing. Append it so `semanage` works.
  selinuxPython = pkgs.selinux-python.overrideAttrs (old: {
    pythonPath = (old.pythonPath or [ ]) ++ [ pkgs.python3Packages.audit.out ];
  });

in
{
  config = lib.mkIf cfg.enable {
    build.scripts.selinuxRelabel = pkgs.writeShellScript "selinux-relabel" ''
      set -euo pipefail
      ${lib.optionalString cfg.verbose "set -x"}

      export PATH="${
        lib.makeBinPath [
          pkgs.policycoreutils
          selinuxPython
        ]
      }"

      # Change the selinux context of the systemd unit files managed by system-manager
      for storeDir in ${lib.concatStringsSep " " unitDir}; do
        fcontextPattern="$storeDir(/.*)?"
        semanage fcontext -m -t ${cfg.unitContext} "$fcontextPattern" \
          || semanage fcontext -a -t ${cfg.unitContext} "$fcontextPattern"
        restorecon ${lib.optionalString cfg.verbose "-v"} -R -F "$storeDir"
      done
    '';
  };
  # Create an option to enable selinux compatibility
  options.system-manager.selinux = {
    enable = lib.mkEnableOption "SELinux context management for system-manager generated files";
    verbose = lib.mkEnableOption "verbose output (command tracing and tool -v flags) for SELinux relabeling";
    unitContext = lib.mkOption {
      type = lib.types.str;
      default = "systemd_unit_file_t";
      description = "SELinux type applied to system-manager generated systemd unit files.";
    };
  };
}
