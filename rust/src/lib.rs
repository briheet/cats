pub mod aggregation;
pub mod cli;
pub mod collectors;
pub mod config;
pub mod domain;
pub mod profiling;
pub mod snapshot;
pub mod storage;
pub mod telemetry;
pub mod theme;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;
