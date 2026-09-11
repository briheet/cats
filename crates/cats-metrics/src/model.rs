use cats_core::theme::Theme;
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Memory {
    pub used: u64,
    pub total: u64,
    pub swap_used: u64,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Network {
    pub interface: String,
    pub received_per_second: Option<f64>,
    pub transmitted_per_second: Option<f64>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Disk {
    pub available: u64,
    pub total: u64,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Battery {
    pub percent: f64,
    pub charging: Option<bool>,
    pub plugged_in: Option<bool>,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Thermal {
    Nominal,
    Fair,
    Serious,
    Critical,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Point {
    pub time: u64,
    pub cpu_percent: Option<f32>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct State {
    pub schema_version: u32,
    pub generated_at: u64,
    pub theme: Theme,
    pub cpu_percent: Option<f32>,
    pub memory: Option<Memory>,
    pub networks: Vec<Network>,
    pub disk: Option<Disk>,
    pub battery: Option<Battery>,
    pub thermal: Option<Thermal>,
    pub low_power_mode: bool,
    pub history: VecDeque<Point>,
}

impl State {
    pub fn new(theme: Theme) -> Self {
        Self {
            schema_version: 1,
            generated_at: 0,
            theme,
            cpu_percent: None,
            memory: None,
            networks: Vec::new(),
            disk: None,
            battery: None,
            thermal: None,
            low_power_mode: false,
            history: VecDeque::new(),
        }
    }
    pub fn record(&mut self, time: u64) {
        self.generated_at = time;
        self.history
            .retain(|p| p.time <= time && time - p.time < 120);
        if self.history.len() == 60 {
            self.history.pop_front();
        }
        self.history.push_back(Point {
            time,
            cpu_percent: self.cpu_percent,
        });
    }
}

/// New/reset counters and wake gaps are unavailable, never fabricated zero rates.
pub fn rate(previous: Option<u64>, current: u64, seconds: f64) -> Option<f64> {
    if !(0.0..=10.0).contains(&seconds) || seconds == 0.0 {
        return None;
    }
    Some(current.checked_sub(previous?)? as f64 / seconds)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rates_handle_boundaries() {
        assert_eq!(rate(Some(100), 500, 2.0), Some(200.0));
        for (old, now, elapsed) in [
            (None, 100, 2.),
            (Some(500), 100, 2.),
            (Some(0), 100, 0.),
            (Some(0), 100, 11.),
            (Some(0), 100, f64::NAN),
        ] {
            assert_eq!(rate(old, now, elapsed), None);
        }
    }
    #[test]
    fn history_is_bounded_and_expires() {
        let mut state = State::new(Theme::default());
        for time in 0..200 {
            state.record(time);
        }
        assert_eq!(state.history.len(), 60);
        state.record(1000);
        assert_eq!(state.history.len(), 1);
        assert_eq!(
            serde_json::from_slice::<State>(&serde_json::to_vec(&state).unwrap()).unwrap(),
            state
        );
    }
}
