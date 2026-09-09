use std::{collections::BTreeMap, time::Instant};
use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, System};

pub struct Metrics {
    pub enabled: bool,
    pub events: usize,
    pub errors: u64,
    pub snapshots: usize,
    samples: BTreeMap<&'static str, Vec<f64>>,
    start: Instant,
    system: System,
}
impl Metrics {
    pub fn new(enabled: bool) -> Self {
        Self {
            enabled,
            events: 0,
            errors: 0,
            snapshots: 0,
            samples: BTreeMap::new(),
            start: Instant::now(),
            system: System::new(),
        }
    }
    pub fn record(&mut self, name: &'static str, start: Instant) {
        if self.enabled {
            let s = self.samples.entry(name).or_default();
            if s.len() < 1024 {
                s.push(start.elapsed().as_secs_f64() * 1000.);
            }
        }
    }
    pub fn report(&mut self, dropped: u64) {
        if !self.enabled {
            return;
        }
        let pid = Pid::from_u32(std::process::id());
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::Some(&[pid]),
            true,
            ProcessRefreshKind::nothing().with_cpu().with_memory(),
        );
        let (cpu, rss) = self
            .system
            .process(pid)
            .map(|p| (p.cpu_usage(), p.memory() / 1024))
            .unwrap_or_default();
        for (stage, values) in &mut self.samples {
            values.sort_by(f64::total_cmp);
            if !values.is_empty() {
                tracing::info!(
                    stage,
                    p95_ms = values[(values.len() - 1) * 95 / 100],
                    "latency"
                );
            }
            values.clear();
        }
        tracing::info!(
            cpu,
            rss_kb = rss,
            events_per_sec = self.events as f64 / self.start.elapsed().as_secs_f64(),
            collector_errors = self.errors,
            snapshots = self.snapshots,
            coalesced_notifications = dropped,
            "profile"
        );
        self.start = Instant::now();
        self.events = 0;
        self.snapshots = 0;
    }
}
