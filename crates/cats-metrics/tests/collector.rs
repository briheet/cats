use std::{fs, process::Command};

fn command(directory: &std::path::Path) -> Command {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_cats-metrics"));
    cmd.env("HOME", directory)
        .env("XDG_CONFIG_HOME", directory.join("config"))
        .env_remove("CATS_METRICS_CONFIG")
        .env_remove("CATS_METRICS_DATA_DIR");
    cmd
}

#[test]
fn configuration_is_independent_strict_and_read_only() {
    let temp = tempfile::tempdir().unwrap();
    let output = command(temp.path())
        .env("CATS_LLM_DATA_DIR", "/must-not-be-used")
        .arg("config")
        .output()
        .unwrap();
    assert!(output.status.success());
    let config: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        config["data_dir"],
        temp.path()
            .join("Library/Application Support/CatsMetrics")
            .to_str()
            .unwrap()
    );
    assert!(!temp.path().join("Library").exists());
    let file = temp.path().join("config.toml");
    for text in [
        "budget-usd = 20",
        "data-dir = 'relative'",
        "theme = 'missing'",
        "network-interface = ''",
    ] {
        fs::write(&file, text).unwrap();
        assert!(
            !command(temp.path())
                .arg("--config")
                .arg(&file)
                .arg("config")
                .output()
                .unwrap()
                .status
                .success()
        );
    }
    fs::write(&file, "theme = 'nord'").unwrap();
    let output = command(temp.path())
        .arg("--config")
        .arg(file)
        .arg("config")
        .output()
        .unwrap();
    let config: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(config["theme"]["colors"]["surface"], "#2e3440");
}

#[test]
fn native_sampling_writes_only_ephemeral_metrics() {
    let temp = tempfile::tempdir().unwrap();
    let data = temp.path().join("metrics");
    let output = command(temp.path())
        .arg("--data-dir")
        .arg(&data)
        .arg("--once")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let state: cats_metrics::model::State =
        serde_json::from_slice(&fs::read(data.join("state.json")).unwrap()).unwrap();
    assert_eq!(state.history.len(), 2);
    assert!(state.history[0].cpu_percent.is_none());
    assert!(
        state
            .cpu_percent
            .is_some_and(|value| (0.0..=100.0).contains(&value))
    );
    assert!(
        state
            .memory
            .is_some_and(|memory| memory.total > 0 && memory.used <= memory.total)
    );
    assert_eq!(fs::read_dir(&data).unwrap().count(), 3);
    assert_eq!(
        fs::read_to_string(data.join("heartbeat")).unwrap(),
        state.generated_at.to_string()
    );
}

#[test]
fn refuses_symbolic_link_lock_and_preserves_target() {
    let temp = tempfile::tempdir().unwrap();
    let target = temp.path().join("outside");
    fs::write(&target, "preserve").unwrap();
    std::os::unix::fs::symlink(&target, temp.path().join("collector.lock")).unwrap();
    assert!(
        !command(temp.path())
            .arg("--data-dir")
            .arg(temp.path())
            .arg("--once")
            .output()
            .unwrap()
            .status
            .success()
    );
    assert_eq!(fs::read_to_string(target).unwrap(), "preserve");
}
