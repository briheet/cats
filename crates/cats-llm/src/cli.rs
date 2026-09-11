use clap::{Parser, Subcommand};
use std::{ffi::OsString, path::PathBuf};

#[derive(Debug, Parser)]
#[command(version, about = "Local AI-agent telemetry for macOS")]
pub struct Cli {
    /// Import available telemetry, write a snapshot, and exit.
    #[arg(long)]
    pub once: bool,
    /// Emit CPU, memory, ingestion, and latency measurements.
    #[arg(long)]
    pub profile: bool,
    /// Override the local telemetry storage directory.
    #[arg(long, env = "CATS_LLM_DATA_DIR", global = true)]
    pub data_dir: Option<PathBuf>,
    /// Daily budget in USD.
    #[arg(long, env = "CATS_LLM_BUDGET_USD", global = true, value_parser = positive_budget)]
    pub budget: Option<f64>,
    /// TOML configuration (defaults to $XDG_CONFIG_HOME/cats-llm/config.toml).
    #[arg(short, long, env = "CATS_LLM_CONFIG", global = true)]
    pub config: Option<PathBuf>,
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Print the built-in themes and their resolved colors as JSON.
    Themes,
    /// Validate configuration and print the resolved settings without starting Cats.
    Config,
    /// Delete the database without a backup, reimport available logs, and exit.
    Reset {
        /// Confirm permanent deletion of stored usage and ingestion cursors.
        #[arg(long)]
        yes: bool,
    },
    /// Launch an agent that Cats can pause and resume.
    Run {
        name: String,
        #[arg(last = true, required = true)]
        command: Vec<OsString>,
    },
}

fn positive_budget(value: &str) -> Result<f64, String> {
    value
        .parse::<f64>()
        .ok()
        .filter(|n| n.is_finite() && *n > 0.)
        .ok_or_else(|| "budget must be a positive finite number".into())
}
