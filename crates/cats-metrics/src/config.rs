use cats_core::{
    Result,
    theme::{self, Theme},
};
use serde::{Deserialize, Serialize};
use std::{env, path::PathBuf};

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]
struct Settings {
    data_dir: Option<PathBuf>,
    theme: Option<String>,
    network_interface: Option<String>,
}

#[derive(Serialize)]
pub struct Config {
    pub data_dir: PathBuf,
    pub theme: Theme,
    pub network_interface: Option<String>,
}

impl Config {
    pub fn load(file: Option<PathBuf>, data_dir: Option<PathBuf>) -> Result<Self> {
        let home = PathBuf::from(env::var_os("HOME").ok_or("HOME is missing")?);
        let explicit = file.is_some();
        let file = file.unwrap_or_else(|| {
            env::var_os("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .filter(|p| p.is_absolute())
                .unwrap_or_else(|| home.join(".config"))
                .join("cats-metrics/config.toml")
        });
        let settings: Settings = match std::fs::read_to_string(&file) {
            Ok(text) => toml::from_str(&text)?,
            Err(e) if !explicit && e.kind() == std::io::ErrorKind::NotFound => Settings::default(),
            Err(e) => return Err(e.into()),
        };
        let data_dir = data_dir
            .or(settings.data_dir)
            .unwrap_or_else(|| home.join("Library/Application Support/CatsMetrics"));
        let data_dir = data_dir
            .strip_prefix("~")
            .map(|tail| home.join(tail))
            .unwrap_or(data_dir);
        if !data_dir.is_absolute() {
            return Err("data-dir must be absolute or start with ~/".into());
        }
        if settings
            .network_interface
            .as_ref()
            .is_some_and(|s| s.is_empty())
        {
            return Err("network-interface cannot be empty".into());
        }
        Ok(Self {
            data_dir,
            theme: theme::resolve(
                settings.theme.as_deref().unwrap_or("cats"),
                &file
                    .parent()
                    .unwrap_or(std::path::Path::new("."))
                    .join("themes"),
            )?,
            network_interface: settings.network_interface,
        })
    }
}
