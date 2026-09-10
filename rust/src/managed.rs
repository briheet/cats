//! Launch and control only the child process group owned by this wrapper.
use crate::shutdown;
use cats::{Result, config::Config, domain::AgentStatus};
use serde::Deserialize;
use std::{
    fs::{self, File},
    time::{Duration, Instant},
};

#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Action {
    Pause,
    Resume,
}

#[derive(Deserialize)]
struct Control {
    action: Action,
}

pub fn run(config: &Config, name: &str, command: &[std::ffi::OsString]) -> Result<()> {
    use std::{os::unix::process::CommandExt, process::Command};
    let executable = command.first().ok_or("An agent command is required")?;
    let mut child = Command::new(executable)
        .args(&command[1..])
        .process_group(0)
        .spawn()?;
    let result = monitor(config, name, &mut child);
    // Clean up even when opening or publishing the lifecycle log failed.
    if matches!(child.try_wait(), Ok(None)) {
        let _ = signal_group(&child, libc::SIGCONT);
        let _ = signal_group(&child, libc::SIGTERM);
    }
    result
}

fn signal_group(child: &std::process::Child, signal: libc::c_int) -> std::io::Result<()> {
    // SAFETY: callers only pass an unreaped child created with process_group(0).
    if unsafe { libc::kill(-(child.id() as i32), signal) } == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

fn monitor(config: &Config, name: &str, child: &mut std::process::Child) -> Result<()> {
    use std::io::Write;
    let id = format!(
        "local-{}-{}",
        child.id(),
        chrono::Utc::now().timestamp_millis()
    );
    let path = config.local_dir.join(format!("{id}.jsonl"));
    File::options().create_new(true).append(true).open(&path)?;
    let publish = |status: AgentStatus| -> Result<()> {
        // Closing after each lifecycle record makes FSEvents deliver the update promptly.
        let mut file = File::options().append(true).open(&path)?;
        writeln!(
            file,
            "{}",
            serde_json::json!({"timestamp":chrono::Utc::now().to_rfc3339(),"session_id":id,"agent":cats::telemetry::label(name),"status":status})
        )?;
        file.flush()?;
        Ok(())
    };
    let mut paused = false;
    publish(AgentStatus::Running)?;
    let mut last = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            publish(if status.success() {
                AgentStatus::Completed
            } else {
                AgentStatus::Failed
            })?;
            return if status.success() {
                Ok(())
            } else {
                Err(format!("Agent exited: {status}").into())
            };
        }
        if shutdown::requested() {
            publish(AgentStatus::Failed)?;
            return Ok(());
        }
        let desired = fs::read_to_string(config.data_dir.join("cats-control.json"))
            .ok()
            .and_then(|x| serde_json::from_str::<Control>(&x).ok());
        let pause = desired.is_some_and(|control| control.action == Action::Pause);
        if pause != paused {
            let signal = if pause { libc::SIGSTOP } else { libc::SIGCONT };
            if signal_group(child, signal).is_ok() {
                paused = pause;
                publish(if paused {
                    AgentStatus::Waiting
                } else {
                    AgentStatus::Running
                })?;
            }
        }
        if last.elapsed() >= Duration::from_secs(60) {
            publish(if paused {
                AgentStatus::Waiting
            } else {
                AgentStatus::Running
            })?;
            last = Instant::now();
        }
        std::thread::sleep(Duration::from_secs(1));
    }
}
