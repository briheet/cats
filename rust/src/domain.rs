//! Domain values shared by parsers, storage, and snapshots.
use rusqlite::types::{FromSql, FromSqlError, FromSqlResult, ToSql, ToSqlOutput, ValueRef};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum ProviderKind {
    Claude,
    Codex,
    #[default]
    Local,
}

impl ProviderKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Claude => "Claude",
            Self::Codex => "Codex",
            Self::Local => "Local",
        }
    }
}

impl std::fmt::Display for ProviderKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum AgentStatus {
    // Empty status is present in cursors written before any lifecycle event.
    #[default]
    #[serde(rename = "")]
    Unknown,
    Running,
    Waiting,
    Completed,
    Failed,
    Idle,
}

impl AgentStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Unknown => "",
            Self::Running => "running",
            Self::Waiting => "waiting",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Idle => "idle",
        }
    }

    pub fn at(self, provider: ProviderKind, age_seconds: i64) -> Self {
        match (provider, self, age_seconds > 300) {
            // Legacy Codex completion records describe turns, not closed sessions.
            (ProviderKind::Codex, Self::Completed | Self::Waiting, false) => Self::Waiting,
            (ProviderKind::Codex, Self::Completed | Self::Waiting, true) => Self::Idle,
            (_, Self::Running, true) => Self::Waiting,
            _ => self,
        }
    }

    pub fn display_order(self) -> u8 {
        match self {
            Self::Running => 0,
            Self::Waiting => 1,
            Self::Failed => 2,
            _ => 3,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum BudgetState {
    #[default]
    Normal,
    Elevated,
    Warning,
    Exceeded,
}

// SQLite retains the same text representation as the JSON protocol.
macro_rules! sqlite_text {
    ($kind:ty) => {
        impl ToSql for $kind {
            fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
                Ok(self.as_str().into())
            }
        }
        impl FromSql for $kind {
            fn column_result(value: ValueRef<'_>) -> FromSqlResult<Self> {
                serde_json::from_value(serde_json::Value::String(value.as_str()?.into()))
                    .map_err(|error| FromSqlError::Other(Box::new(error)))
            }
        }
    };
}
sqlite_text!(ProviderKind);
sqlite_text!(AgentStatus);
