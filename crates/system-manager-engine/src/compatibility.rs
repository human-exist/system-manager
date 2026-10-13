pub(crate) mod selinux {
    use crate::StorePath;

    pub fn relabel_systemd_files(store_path: &StorePath) -> anyhow::Result<()> {
        let script = store_path.store_path.join("bin").join("selinux-relabel");
        if !script.exists() {
            return Ok(());
        }

        let status = std::process::Command::new(&script)
            .stderr(std::process::Stdio::inherit())
            .stdout(std::process::Stdio::inherit())
            .status()?;
        if !status.success() {
            anyhow::bail!("SELinux relabel script failed with status: {status}");
        }
        Ok(())
    }
}
