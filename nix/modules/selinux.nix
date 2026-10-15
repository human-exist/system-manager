{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.system-manager.selinux;

  # Nixpkgs' selinux-python omits the `audit` module from its pythonPath, but
  # seobject.py needs it for fcontext auditing. Append it so `semanage` works.
  selinuxPython = pkgs.selinux-python.overrideAttrs (old: {
    pythonPath = (old.pythonPath or [ ]) ++ [ pkgs.python3Packages.audit.out ];
  });

  # One type for the whole store rather than one per path: the label lives on
  # the inode, so per-path types would let auto-optimise-store hard-link two
  # different labels onto the same file.
  storeTypeRules = [
    {
      domain = cfg.initDomain;
      class = "file";
      permissions = [
        "execute"
        "execute_no_trans"
        "getattr"
        "open"
        "read"
        "map"
      ];
    }
    {
      domain = cfg.daemonDomain;
      class = "file";
      permissions = [
        "append"
        "create"
        "execute"
        "execute_no_trans"
        "getattr"
        "ioctl"
        "link"
        "lock"
        "map"
        "open"
        "read"
        "rename"
        "setattr"
        "unlink"
        "write"
      ];
    }
    {
      domain = cfg.daemonDomain;
      class = "dir";
      permissions = [
        "add_name"
        "create"
        "getattr"
        "ioctl"
        "link"
        "lock"
        "open"
        "read"
        "remove_name"
        "rename"
        "search"
        "setattr"
        "unlink"
        "write"
      ];
    }
    {
      domain = cfg.daemonDomain;
      class = "filesystem";
      permissions = [ "associate" ];
    }
  ];

  nixStorePolicy = pkgs.writeText "nix-store.cil" ''
    (type ${cfg.storeContext})
    (typeattributeset file_type (${cfg.storeContext}))
    (roletype object_r ${cfg.storeContext})
    ${lib.concatMapStringsSep "\n" (
      rule:
      "(allow ${rule.domain} ${cfg.storeContext} (${rule.class} (${lib.concatStringsSep " " rule.permissions})))"
    ) storeTypeRules}
  '';

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

      # Change the selinux context of the store
      # Strictly ordered; each step is a precondition for the next.
      semodule -i ${nixStorePolicy}
      semanage fcontext -a -t ${cfg.storeContext} '${cfg.storePath}(/.*)?' \
        || semanage fcontext -m -t ${cfg.storeContext} '${cfg.storePath}(/.*)?'
      restorecon ${lib.optionalString cfg.verbose "-v"} -R ${cfg.storePath}
    '';
  };
  # Create an option to enable selinux compatibility
  options.system-manager.selinux = {
    enable = lib.mkEnableOption "SELinux context management for system-manager generated files";
    verbose = lib.mkEnableOption "verbose output (command tracing and tool -v flags) for SELinux relabeling";

    storePath = lib.mkOption {
      type = lib.types.str;
      default = "/nix/store";
      description = lib.mdDoc ''
        Path of the Nix store to label. Change this only if the store was
        relocated on this host.
      '';
    };

    storeContext = lib.mkOption {
      type = lib.types.str;
      default = "nix_store_t";
      description = lib.mdDoc ''
        SELinux type installed for {option}.storePath{option}.storePath. The
        module defines this type in the running policy, so it must not already
        exist.
      '';
    };

    initDomain = lib.mkOption {
      type = lib.types.str;
      default = "init_t";
      description = lib.mdDoc ''
        SELinux domain of the service manager. Granted permission to execute
        store binaries so units whose `ExecStart` lives in the store do not
        fail with `203/EXEC`.
      '';
    };

    daemonDomain = lib.mkOption {
      type = lib.types.str;
      default = "unconfined_service_t";
      description = lib.mdDoc ''
        SELinux domain of the Nix daemon. Granted permission to manage
        {option}.storePath so that labelling it does not break builds.
      '';
    };

  };
}
