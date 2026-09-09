use crate::Result;
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, path::Path};

pub const BUILTINS: &[(&str, &str)] = &[
    ("cats", include_str!("../../themes/cats.toml")),
    ("nord", include_str!("../../themes/nord.toml")),
    ("rose-pine", include_str!("../../themes/rose-pine.toml")),
    (
        "rose-pine-moon",
        include_str!("../../themes/rose-pine-moon.toml"),
    ),
    (
        "rose-pine-dawn",
        include_str!("../../themes/rose-pine-dawn.toml"),
    ),
];

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "kebab-case")]
pub enum Appearance {
    #[default]
    System,
    Dark,
    Light,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Theme {
    pub appearance: Appearance,
    pub colors: BTreeMap<String, String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Definition {
    inherits: Option<String>,
    appearance: Option<Appearance>,
    #[serde(default)]
    colors: BTreeMap<String, String>,
}

pub fn resolve(name: &str, directory: &Path) -> Result<Theme> {
    fn read(name: &str, directory: &Path, stack: &mut Vec<String>) -> Result<Theme> {
        if name.is_empty()
            || !name
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"-_".contains(&c))
        {
            return Err(format!("Invalid theme name: {name}").into());
        }
        if stack.len() >= 16 || stack.iter().any(|n| n == name) {
            return Err(format!("Theme inheritance cycle or depth limit: {name}").into());
        }
        stack.push(name.into());
        let source = match BUILTINS.iter().find(|(n, _)| *n == name) {
            Some((_, source)) => source.to_string(),
            None => std::fs::read_to_string(directory.join(format!("{name}.toml")))?,
        };
        let definition: Definition = toml::from_str(&source)?;
        let mut theme = match definition.inherits {
            Some(parent) => read(&parent, directory, stack)?,
            None => Theme::default(),
        };
        if let Some(appearance) = definition.appearance {
            theme.appearance = appearance;
        }
        for (key, value) in definition.colors {
            if ![
                "surface",
                "text",
                "muted",
                "accent",
                "secondary",
                "claude",
                "codex",
                "warning",
                "error",
            ]
            .contains(&key.as_str())
            {
                return Err(format!("Unknown theme color: {key}").into());
            }
            if value.len() != 7
                || !value.starts_with('#')
                || !value[1..].bytes().all(|c| c.is_ascii_hexdigit())
            {
                return Err(format!("Theme color {key} must be #RRGGBB").into());
            }
            theme.colors.insert(key, value);
        }
        stack.pop();
        Ok(theme)
    }
    read(name, directory, &mut Vec::new())
}
