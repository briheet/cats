use cats_core::{Result, atomic_write};
use cats_metrics::{config::Config, model::State, sampler::Sampler};
use clap::{Parser, Subcommand};
use std::{
    fs::{self, OpenOptions},
    os::{
        fd::AsRawFd,
        unix::fs::{OpenOptionsExt, PermissionsExt},
    },
    path::PathBuf,
    sync::atomic::{AtomicBool, Ordering},
    time::Duration,
};

#[derive(Parser)]
#[command(version, about = "Lightweight local macOS system metrics")]
struct Cli {
    #[arg(long, short, env = "CATS_METRICS_CONFIG", global = true)]
    config: Option<PathBuf>,
    #[arg(long, env = "CATS_METRICS_DATA_DIR", global = true)]
    data_dir: Option<PathBuf>,
    /// Take two readings to establish CPU/network rates, write state and exit.
    #[arg(long)]
    once: bool,
    #[command(subcommand)]
    command: Option<Command>,
}
#[derive(Subcommand)]
enum Command {
    Config,
}
static STOP: AtomicBool = AtomicBool::new(false);
extern "C" fn stop(_: libc::c_int) {
    STOP.store(true, Ordering::Relaxed);
}
fn main() -> Result<()> {
    let args = Cli::parse();
    let config = Config::load(args.config, args.data_dir)?;
    if matches!(args.command, Some(Command::Config)) {
        println!("{}", serde_json::to_string_pretty(&config)?);
        return Ok(());
    }
    fs::create_dir_all(&config.data_dir)?;
    let metadata = fs::symlink_metadata(&config.data_dir)?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err("data-dir must be a real directory".into());
    }
    fs::set_permissions(&config.data_dir, fs::Permissions::from_mode(0o700))?;
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(config.data_dir.join("collector.lock"))?;
    // SAFETY: lock remains owned for this entire service; signal handlers only
    // perform an atomic store and do not allocate or access application state.
    unsafe {
        if libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) != 0 {
            return Err("A metrics collector already owns this data directory".into());
        }
        for signal in [libc::SIGINT, libc::SIGTERM] {
            if libc::signal(signal, stop as *const () as usize) == libc::SIG_ERR {
                return Err(std::io::Error::last_os_error().into());
            }
        }
    }
    let mut sampler = Sampler::new(config.network_interface);
    let mut state = State::new(config.theme);
    let mut samples = 0;
    while !STOP.load(Ordering::Relaxed) {
        sampler.sample(&mut state);
        atomic_write(
            &config.data_dir.join("state.json"),
            &serde_json::to_vec(&state)?,
        )?;
        atomic_write(
            &config.data_dir.join("heartbeat"),
            state.generated_at.to_string().as_bytes(),
        )?;
        samples += 1;
        if args.once && samples == 2 {
            break;
        }
        std::thread::sleep(Duration::from_secs(2));
    }
    Ok(())
}
