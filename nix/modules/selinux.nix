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

  # Single SELinux type (`nix_store_t`) labels every store inode.
  # Per-path types would conflict when auto-optimise-store hard-links files.
  storeTypeRules = [
    {
      domain = cfg.initDomain;
      class = "file";
      permissions = [
        #"append"
        #"audit_access"
        #"create"
        #"entrypoint"
        #"execmod"
        "execute"
        "execute_no_trans"
        "getattr"
        #"ioctl"
        #"link"
        #"lock"
        "map"
        #"mounton"
        "open"
        #"quotaon"
        "read"
        #"relabelfrom"
        #"relabelto"
        #"rename"
        #"setattr"
        #"swapon"
        #"unlink"
        #"watch"
        #"watch_mount"
        #"watch_mountns"
        #"watch_reads"
        #"watch_sb"
        #"watch_with_perm"
        #"write"
      ];
    }
    {
      domain = cfg.daemonDomain;
      class = "file";
      permissions = [
        "append"
        #"audit_access"
        "create"
        #"entrypoint"
        #"execmod"
        "execute"
        "execute_no_trans"
        "getattr"
        "ioctl"
        "link"
        "lock"
        "map"
        #"mounton"
        "open"
        #"quotaon"
        "read"
        #"relabelfrom"
        #"relabelto"
        "rename"
        "setattr"
        #"swapon"
        "unlink"
        #"watch"
        #"watch_mount"
        #"watch_mountns"
        #"watch_reads"
        #"watch_sb"
        #"watch_with_perm"
        "write"
      ];
    }
    {
      domain = cfg.daemonDomain;
      class = "dir";
      permissions = [
        "add_name"
        #"append"
        #"audit_access"
        "create"
        #"execmod"
        #"execute"
        "getattr"
        "ioctl"
        "link"
        "lock"
        #"map"
        #"mounton"
        "open"
        #"quotaon"
        "read"
        #"relabelfrom"
        #"relabelto"
        "remove_name"
        "rename"
        #"reparent"
        #"rmdir"
        "search"
        "setattr"
        #"swapon"
        "unlink"
        #"watch"
        #"watch_mount"
        #"watch_mountns"
        #"watch_reads"
        #"watch_sb"
        #"watch_with_perm"
        "write"
      ];
    }
    {
      domain = cfg.daemonDomain;
      class = "filesystem";
      permissions = [
        "associate"
        #"getattr"
        #"mount"
        #"quotaget"
        #"quotamod"
        #"relabelfrom"
        #"relabelto"
        #"remount"
        #"transition"
        #"unmount"
        #"watch"
      ];
    }
    {
      domain = "domain";
      class = "dir";
      permissions = [
        #"add_name"
        #"append"
        #"audit_access"
        #"create"
        #"execmod"
        #"execute"
        "getattr"
        #"ioctl"
        #"link"
        #"lock"
        #"map"
        #"mounton"
        "open"
        #"quotaon"
        "read"
        #"relabelfrom"
        #"relabelto"
        #"remove_name"
        #"rename"
        #"reparent"
        #"rmdir"
        "search"
        #"setattr"
        #"swapon"
        #"unlink"
        #"watch"
        #"watch_mount"
        #"watch_mountns"
        #"watch_reads"
        #"watch_sb"
        #"watch_with_perm"
        #"write"
      ];
    }
    {
      domain = "domain";
      class = "file";
      permissions = [
        #"append"
        #"audit_access"
        #"create"
        #"entrypoint"
        #"execmod"
        #"execute"
        #"execute_no_trans"
        "getattr"
        #"ioctl"
        #"link"
        #"lock"
        "map"
        #"mounton"
        "open"
        #"quotaon"
        "read"
        #"relabelfrom"
        #"relabelto"
        #"rename"
        #"setattr"
        #"swapon"
        #"unlink"
        #"watch"
        #"watch_mount"
        #"watch_mountns"
        #"watch_reads"
        #"watch_sb"
        #"watch_with_perm"
        #"write"
      ];
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
          pkgs.coreutils
          pkgs.policycoreutils
          selinuxPython
        ]
      }"

      # CIL carries no module name, so semodule takes it from the filename and
      # a store path always starts with a hash, which is not a valid name.
      moduleDir="$(mktemp -d)"
      trap 'rm -rf "$moduleDir"' EXIT
      cp ${nixStorePolicy} "$moduleDir/nix_store.cil"

      # Change the selinux context of the store
      # Strictly ordered; each step is a precondition for the next.
      semodule -i "$moduleDir/nix_store.cil"
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
        Path of the Nix store to label.
      '';
    };

    storeContext = lib.mkOption {
      type = lib.types.str;
      default = "nix_store_t";
      description = lib.mdDoc ''
        SELinux type for the store; must not already exist in policy.
      '';
    };

    initDomain = lib.mkOption {
      type = lib.types.str;
      default = "init_t";
      description = lib.mdDoc ''
        Domain of the service manager.
      '';
    };

    daemonDomain = lib.mkOption {
      type = lib.types.str;
      default = "unconfined_service_t";
      description = lib.mdDoc ''
        Domain of the Nix daemon.
      '';
    };

  };
}
