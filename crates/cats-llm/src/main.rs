mod managed;
mod service;
mod shutdown;

use cats_llm::{
    Result,
    cli::{Cli, Command},
    config::Config,
    theme,
};
use clap::Parser;
use std::{collections::BTreeMap, fs, os::unix::fs::PermissionsExt, path::Path};

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "cats_llm=info".into()),
        )
        .with_writer(std::io::stderr)
        .init();
    let mut args = Cli::parse();
    if let Some(Command::Reset { yes }) = args.command {
        if !yes {
            return Err("Reset deletes stored usage without a backup. Pass reset --yes to confirm; stop the collector first.".into());
        }
        args.once = true;
    }
    if matches!(args.command, Some(Command::Themes)) {
        let themes = theme::BUILTINS
            .iter()
            .map(|(name, _)| Ok((*name, theme::resolve(name, Path::new("."))?)))
            .collect::<Result<BTreeMap<_, _>>>()?;
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
    shutdown::install()?;
    if let Some(Command::Run { name, command }) = &args.command {
        managed::run(&config, name, command)
    } else {
        service::run(&args, config)
    }
}
