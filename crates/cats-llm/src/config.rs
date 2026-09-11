use crate::Result;
use crate::domain::ProviderKind;
use serde::{Deserialize, Serialize};
use std::{env, path::PathBuf};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Config {
    pub config_file: PathBuf,
    pub theme: crate::theme::Theme,
    pub data_dir: PathBuf,
    pub claude_dir: PathBuf,
    pub codex_dir: PathBuf,
    pub local_dir: PathBuf,
    pub budget_usd: f64,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields, rename_all = "kebab-case")]
struct Settings {
    budget_usd: Option<f64>,
    data_dir: Option<PathBuf>,
    claude_dir: Option<PathBuf>,
    codex_dir: Option<PathBuf>,
    theme: Option<String>,
}

impl Config {
    pub fn canonicalize(&mut self) {
        for path in [
            &mut self.data_dir,
            &mut self.claude_dir,
            &mut self.codex_dir,
            &mut self.local_dir,
        ] {
            if let Ok(resolved) = std::fs::canonicalize(&*path) {
                *path = resolved;
            }
        }
    }

    pub fn load(
        file: Option<PathBuf>,
        data_dir: Option<PathBuf>,
        budget: Option<f64>,
    ) -> Result<Self> {
        let home = PathBuf::from(env::var_os("HOME").ok_or("HOME is missing")?);
        let explicit = file.is_some();
        let config_file = file.unwrap_or_else(|| {
            env::var_os("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .filter(|p| p.is_absolute())
                .unwrap_or_else(|| home.join(".config"))
                .join("cats-llm/config.toml")
        });
        let settings: Settings = match std::fs::read_to_string(&config_file) {
            Ok(text) => toml::from_str(&text)?,
            Err(error) if !explicit && error.kind() == std::io::ErrorKind::NotFound => {
                Settings::default()
            }
            Err(error) => return Err(error.into()),
        };
        let expand = |path: PathBuf| -> Result<PathBuf> {
            let path = path
                .strip_prefix("~")
                .map(|tail| home.join(tail))
                .unwrap_or(path);
            if !path.is_absolute() {
                return Err("Configured paths must be absolute or start with ~/".into());
            }
            Ok(path)
        };
        let theme = crate::theme::resolve(
            settings.theme.as_deref().unwrap_or("cats"),
            &config_file
                .parent()
                .unwrap_or(std::path::Path::new("."))
                .join("themes"),
        )?;
        let budget_usd = budget.or(settings.budget_usd).unwrap_or(20.);
        if !budget_usd.is_finite() || budget_usd <= 0. {
            return Err("budget-usd must be positive and finite".into());
        }
        let data_dir = expand(
            data_dir
                .or(settings.data_dir)
                .unwrap_or_else(|| home.join("Library/Application Support/CatsLLM")),
        )?;
        Ok(Self {
            config_file,
            theme,
            local_dir: data_dir.join("agents"),
            data_dir,
            claude_dir: expand(settings.claude_dir.unwrap_or_else(|| {
                env::var_os("CLAUDE_CONFIG_DIR")
                    .map(PathBuf::from)
                    .unwrap_or_else(|| home.join(".claude"))
                    .join("projects")
            }))?,
            codex_dir: expand(settings.codex_dir.unwrap_or_else(|| {
                env::var_os("CODEX_HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|| home.join(".codex"))
                    .join("sessions")
            }))?,
            budget_usd,
        })
    }
    pub fn roots(&self) -> [(ProviderKind, &std::path::Path); 3] {
        [
            (ProviderKind::Claude, &self.claude_dir),
            (ProviderKind::Codex, &self.codex_dir),
            (ProviderKind::Local, &self.local_dir),
        ]
    }
}
