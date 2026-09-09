use cats::cli::{Cli, Command};
use cats::{
    Result, aggregation, collectors, config::Config, profiling::Metrics, snapshot, storage::Store,
};
use clap::Parser;
use notify::{RecursiveMode, Watcher};
use std::{
    collections::HashMap,
    fs::{self, File},
    os::fd::AsRawFd,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc,
    },
    time::{Duration, Instant},
};

static STOP: AtomicBool = AtomicBool::new(false);
extern "C" fn stop(_: libc::c_int) {
    STOP.store(true, Ordering::Relaxed);
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "cats=info".into()),
        )
        .with_writer(std::io::stderr)
        .init();
    let args = Cli::parse();
    if matches!(args.command, Some(Command::Themes)) {
        let themes = cats::theme::BUILTINS
            .iter()
            .map(|(name, _)| {
                Ok((
                    *name,
                    cats::theme::resolve(name, std::path::Path::new("."))?,
                ))
            })
            .collect::<Result<std::collections::BTreeMap<_, _>>>()?;
        println!("{}", serde_json::to_string_pretty(&themes)?);
        return Ok(());
    }
    let mut config = Config::load(args.config.clone(), args.data_dir.clone(), args.budget)?;
    if matches!(args.command, Some(Command::Config)) {
        println!("{}", serde_json::to_string_pretty(&config)?);
        return Ok(());
    }
    fs::create_dir_all(&config.local_dir)?;
    fs::set_permissions(&config.data_dir, fs::Permissions::from_mode(0o700))?;
    config.canonicalize();
    unsafe {
        libc::signal(libc::SIGINT, stop as *const () as usize);
        libc::signal(libc::SIGTERM, stop as *const () as usize);
    }
    if let Some(Command::Run { name, command }) = args.command {
        return run_agent(&config, &name, &command);
    }
    let lock = File::options()
        .create(true)
        .truncate(false)
        .write(true)
        .open(config.data_dir.join("collector.lock"))?;
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Err("A collector is already running in this data directory".into());
    }
    let mut store = Store::open(&config.data_dir.join("cats.sqlite"))?;
    let mut metrics = Metrics::new(args.profile);
    let dropped = Arc::new(AtomicU64::new(0));
    let (tx, rx) = mpsc::sync_channel(64);
    let overflow = dropped.clone();
    let mut watcher = notify::recommended_watcher(move |result: notify::Result<notify::Event>| {
        tracing::debug!(event = ?result.as_ref().map(|e| &e.kind), "Filesystem notification");
        if let Ok(e) = result
            && !matches!(e.kind, notify::EventKind::Access(_))
            && tx.try_send(e.paths).is_err()
        {
            overflow.fetch_add(1, Ordering::Relaxed);
        }
    })?;
    let mut watched = Vec::new();
    let mut pending: Vec<(String, PathBuf)> = Vec::new();
    let mut retry: HashMap<PathBuf, (u32, Instant)> = HashMap::new();
    let mut reconcile = Instant::now() - Duration::from_secs(60);
    let mut heartbeat = Instant::now() - Duration::from_secs(60);
    loop {
        let scanning = reconcile.elapsed() >= Duration::from_secs(60);
        if scanning {
            match Config::load(args.config.clone(), args.data_dir.clone(), args.budget) {
                Ok(updated) => {
                    config.theme = updated.theme;
                    config.budget_usd = updated.budget_usd;
                }
                Err(error) => tracing::warn!(%error, "Keeping last valid configuration"),
            }
            for (provider, root) in config.roots() {
                if root.is_dir()
                    && !watched.contains(&root.to_path_buf())
                    && watcher.watch(root, RecursiveMode::Recursive).is_ok()
                {
                    watched.push(root.to_path_buf());
                }
                pending.extend(
                    collectors::files(root)
                        .into_iter()
                        .map(|p| (provider.to_string(), p)),
                );
            }
            reconcile = Instant::now();
        }
        pending.sort();
        pending.dedup();
        let mut continuation = Vec::new();
        for (provider, path) in pending.drain(..) {
            if STOP.load(Ordering::Relaxed) {
                break;
            }
            if retry.get(&path).is_some_and(|(_, at)| Instant::now() < *at) {
                continue;
            }
            let start = Instant::now();
            match collectors::ingest(&mut store, &path, &provider) {
                Ok(batch) => {
                    metrics.events += batch.events;
                    retry.remove(&path);
                    if batch.more {
                        continuation.push((provider, path));
                    }
                }
                Err(error) => {
                    metrics.errors += 1;
                    let attempts = retry.get(&path).map_or(1, |(n, _)| (n + 1).min(8));
                    retry.insert(
                        path,
                        (
                            attempts,
                            Instant::now() + Duration::from_secs(2u64.pow(attempts)),
                        ),
                    );
                    tracing::warn!(collector=provider, retry=attempts, %error, "Collection failed");
                }
            }
            metrics.record("ingest_and_sqlite_write", start);
        }
        let start = Instant::now();
        let mut state = aggregation::aggregate(&store, chrono::Utc::now(), config.budget_usd)?;
        state.theme = config.theme.clone();
        state.collector_errors = retry.len() as u64;
        metrics.record("aggregate_and_sqlite_query", start);
        let start = Instant::now();
        if snapshot::write(&config.data_dir, &state)? {
            metrics.snapshots += 1;
        }
        metrics.record("snapshot_write", start);
        if heartbeat.elapsed() >= Duration::from_secs(60) {
            snapshot::atomic_write(
                &config.data_dir.join("heartbeat"),
                state.generated_at.to_string().as_bytes(),
            )?;
            metrics.report(dropped.swap(0, Ordering::Relaxed));
            heartbeat = Instant::now();
        }
        pending = continuation;
        if args.once {
            if pending.is_empty() {
                break;
            } else {
                continue;
            }
        }
        if STOP.load(Ordering::Relaxed) {
            break;
        }
        if !pending.is_empty() {
            continue;
        }
        loop {
            if let Ok(paths) = rx.recv_timeout(Duration::from_secs(1)) {
                // Coalesce a burst, then immediately process only affected logs.
                let mut paths = paths;
                std::thread::sleep(Duration::from_millis(250));
                for more in rx.try_iter() {
                    paths.extend(more);
                }
                for path in paths {
                    for (provider, root) in config.roots() {
                        if path.starts_with(root) && path.extension().is_some_and(|x| x == "jsonl")
                        {
                            pending.push((provider.into(), path.clone()));
                        }
                    }
                }
                break;
            } else if reconcile.elapsed() >= Duration::from_secs(60) || STOP.load(Ordering::Relaxed)
            {
                break;
            }
        }
    }
    tracing::info!("Collector stopped");
    Ok(())
}

fn run_agent(config: &Config, name: &str, command: &[std::ffi::OsString]) -> Result<()> {
    use std::{io::Write, os::unix::process::CommandExt, process::Command};
    let mut child = Command::new(&command[0])
        .args(&command[1..])
        .process_group(0)
        .spawn()?;
    let id = format!(
        "local-{}-{}",
        child.id(),
        chrono::Utc::now().timestamp_millis()
    );
    let path = config.local_dir.join(format!("{id}.jsonl"));
    File::options().create_new(true).append(true).open(&path)?;
    let publish = |status: &str| -> Result<()> {
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
    publish("running")?;
    let mut last = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            publish(if status.success() {
                "completed"
            } else {
                "failed"
            })?;
            return if status.success() {
                Ok(())
            } else {
                Err(format!("Agent exited: {status}").into())
            };
        }
        if STOP.load(Ordering::Relaxed) {
            unsafe {
                libc::kill(-(child.id() as i32), libc::SIGCONT);
                libc::kill(-(child.id() as i32), libc::SIGTERM);
            }
            publish("failed")?;
            return Ok(());
        }
        let desired = fs::read_to_string(config.data_dir.join("cats-control.json"))
            .ok()
            .and_then(|x| serde_json::from_str::<serde_json::Value>(&x).ok());
        let pause = desired.as_ref().and_then(|x| x["action"].as_str()) == Some("pause");
        if pause != paused
            && unsafe {
                libc::kill(
                    -(child.id() as i32),
                    if pause { libc::SIGSTOP } else { libc::SIGCONT },
                )
            } == 0
        {
            paused = pause;
            publish(if paused { "waiting" } else { "running" })?;
        }
        if last.elapsed() >= Duration::from_secs(60) {
            publish(if paused { "waiting" } else { "running" })?;
            last = Instant::now();
        }
        std::thread::sleep(Duration::from_secs(1));
    }
}
