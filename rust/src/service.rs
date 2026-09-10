//! Bounded ingestion, filesystem notifications and snapshot publication.
use crate::shutdown;
use cats::{
    Result, aggregation, cli::Cli, collectors, config::Config, profiling::Metrics, snapshot,
    storage::Store,
};
use notify::{RecursiveMode, Watcher};
use std::{
    collections::HashMap,
    fs::File,
    os::fd::AsRawFd,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
        mpsc,
    },
    time::{Duration, Instant},
};

struct Retry {
    attempts: u32,
    ready_at: Instant,
}

pub fn run(args: &Cli, mut config: Config) -> Result<()> {
    let lock = File::options()
        .create(true)
        .truncate(false)
        .write(true)
        .open(config.data_dir.join("collector.lock"))?;
    // SAFETY: lock owns a valid descriptor and stays alive for the entire service.
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
    let mut retry: HashMap<PathBuf, Retry> = HashMap::new();
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
                    collectors::files(root)?
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
            if shutdown::requested() {
                break;
            }
            if retry
                .get(&path)
                .is_some_and(|retry| Instant::now() < retry.ready_at)
            {
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
                    if error
                        .downcast_ref::<std::io::Error>()
                        .is_some_and(|e| e.kind() == std::io::ErrorKind::PermissionDenied)
                    {
                        return Err(error);
                    }
                    metrics.errors += 1;
                    let attempts = retry
                        .get(&path)
                        .map_or(1, |retry| (retry.attempts + 1).min(8));
                    retry.insert(
                        path,
                        Retry {
                            attempts,
                            ready_at: Instant::now() + Duration::from_secs(2u64.pow(attempts)),
                        },
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
        if shutdown::requested() {
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
            } else if reconcile.elapsed() >= Duration::from_secs(60) || shutdown::requested() {
                break;
            }
        }
    }
    tracing::info!("Collector stopped");
    Ok(())
}
