use crate::activate;

use super::ActivationResult;
use anyhow::Context;
use std::collections::HashSet;
use std::path::PathBuf;
use std::process;

type TmpFilesActivationResult = ActivationResult<()>;

pub fn activate(etc_tree: &HashSet<PathBuf>) -> TmpFilesActivationResult {
    let tmp_files_prefix = PathBuf::from("/etc/tmpfiles.d");
    // List and collect managed files under /etc/tmpFiles.d
    let tmpfiles_conf_files: Vec<&str> = etc_tree
        .iter()
        .filter_map(|p| {
            if p.starts_with(&tmp_files_prefix) {
                p.to_str()
            } else {
                None
            }
        })
        .collect();
    let mut cmd = process::Command::new("systemd-tmpfiles");
    cmd.arg("--create")
        .arg("--remove")
        .args(tmpfiles_conf_files);
    log::debug!("running {:#?}", cmd);
    let output = cmd
        .stdout(process::Stdio::inherit())
        .stderr(process::Stdio::inherit())
        .output()
        .with_context(|| {
            format!(
                "failed to spawn systemd-tmpfiles; PATH={:?}",
                std::env::var_os("PATH")
            )
        })
        .map_err(|e| activate::ActivationError::WithPartialResult {
            result: (),
            source: e,
        })?; // temporary debugging output

    output.status.success().then_some(()).ok_or_else(|| {
        activate::ActivationError::WithPartialResult {
            result: (),
            source: anyhow::anyhow!(
                "Error while creating tmpfiles\nstdout: {}\nstderr: {}",
                String::from_utf8_lossy(output.stdout.as_ref()),
                String::from_utf8_lossy(output.stderr.as_ref())
            ),
        }
    })
}
