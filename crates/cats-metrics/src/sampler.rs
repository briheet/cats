use crate::{
    model::{self, Disk, Memory, Network, State},
    platform,
};
use std::{
    collections::HashMap,
    path::Path,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use sysinfo::{Disks, Networks, System};

pub struct Sampler {
    system: System,
    networks: Networks,
    previous: HashMap<String, (u64, u64)>,
    last: Option<Instant>,
    last_wall: Option<u64>,
    power_at: Option<Instant>,
    disk_at: Option<Instant>,
    interface: Option<String>,
}
impl Sampler {
    pub fn new(interface: Option<String>) -> Self {
        Self {
            system: System::new(),
            networks: Networks::new(),
            previous: HashMap::new(),
            last: None,
            last_wall: None,
            power_at: None,
            disk_at: None,
            interface,
        }
    }
    pub fn sample(&mut self, state: &mut State) {
        let now = Instant::now();
        let wall = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        // Darwin's monotonic clock may exclude sleep; use wall time only to
        // invalidate wake/clock-change gaps, never as the rate denominator.
        let gap = self
            .last_wall
            .is_some_and(|last| wall < last || wall - last > 10);
        let seconds = self
            .last
            .map(|last| now.duration_since(last).as_secs_f64())
            .filter(|_| !gap)
            .unwrap_or(0.);
        self.system.refresh_cpu_usage();
        self.system.refresh_memory();
        let cpu = self.system.global_cpu_usage();
        state.cpu_percent =
            (self.last.is_some() && seconds > 0. && seconds <= 10. && cpu.is_finite())
                .then_some(cpu.clamp(0., 100.));
        let total = self.system.total_memory();
        state.memory = (total > 0).then(|| Memory {
            used: self.system.used_memory().min(total),
            total,
            swap_used: self.system.used_swap(),
        });
        self.networks.refresh(true);
        let mut previous = HashMap::new();
        state.networks = self
            .networks
            .iter()
            .filter(|(name, _)| {
                // Physical interfaces avoid counting the same VPN traffic twice. An
                // explicit interface can select a tunnel instead; never sum both.
                self.interface
                    .as_ref()
                    .map_or_else(|| name.starts_with("en"), |selected| selected == *name)
            })
            .map(|(name, data)| {
                let received = data.total_received();
                let transmitted = data.total_transmitted();
                previous.insert(name.clone(), (received, transmitted));
                let old = self.previous.get(name);
                Network {
                    interface: name.clone(),
                    received_per_second: model::rate(old.map(|v| v.0), received, seconds),
                    transmitted_per_second: model::rate(old.map(|v| v.1), transmitted, seconds),
                }
            })
            .collect();
        // Rank the display interface here; Swift does not aggregate counters.
        state.networks.sort_by(|a, b| {
            let traffic = |n: &Network| {
                n.received_per_second.unwrap_or(0.) + n.transmitted_per_second.unwrap_or(0.)
            };
            traffic(b)
                .total_cmp(&traffic(a))
                .then_with(|| a.interface.cmp(&b.interface))
        });
        self.previous = previous;
        if gap
            || self
                .power_at
                .is_none_or(|last| now.duration_since(last) >= Duration::from_secs(30))
        {
            (state.battery, state.thermal, state.low_power_mode) = platform::power();
            self.power_at = Some(now);
        }
        if gap
            || self
                .disk_at
                .is_none_or(|last| now.duration_since(last) >= Duration::from_secs(60))
        {
            let disks = Disks::new_with_refreshed_list();
            let disk = disks
                .iter()
                .find(|d| d.mount_point() == Path::new("/System/Volumes/Data"))
                .or_else(|| disks.iter().find(|d| d.mount_point() == Path::new("/")));
            state.disk = disk.filter(|d| d.total_space() > 0).map(|d| Disk {
                available: d.available_space(),
                total: d.total_space(),
            });
            self.disk_at = Some(now);
        }
        state.record(wall);
        self.last = Some(now);
        self.last_wall = Some(wall);
    }
}
