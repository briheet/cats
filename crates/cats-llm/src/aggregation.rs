use crate::domain::{AgentStatus, BudgetState, ProviderKind};
use crate::{Result, storage::Store};
use chrono::{DateTime, Local, NaiveDate, NaiveTime, TimeZone, Utc};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Today {
    pub spend_usd: f64,
    pub budget_usd: f64,
    pub budget_fraction: f64,
    pub budget_state: BudgetState,
    pub burn_rate_per_hour: f64,
    pub projected_daily_spend: Option<f64>,
    pub tokens_total: u64,
    pub tokens_input: u64,
    pub tokens_output: u64,
    pub tokens_cache: u64,
    pub unpriced_events: u64,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Provider {
    pub name: ProviderKind,
    pub spend_usd: f64,
    pub tokens: u64,
    pub fraction: f64,
    pub agent_count: u64,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Agent {
    pub id: String,
    pub name: String,
    pub provider: ProviderKind,
    pub status: AgentStatus,
    pub last_activity_at: Option<i64>,
    pub tokens: u64,
    pub spend_usd: f64,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct History {
    pub hourly_spend: Vec<f64>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct State {
    pub theme: crate::theme::Theme,
    pub schema_version: u32,
    pub generated_at: i64,
    pub last_event_at: Option<i64>,
    pub has_usage: bool,
    pub today: Today,
    pub providers: Vec<Provider>,
    pub agents: Vec<Agent>,
    pub active_agents: u64,
    pub waiting_agents: u64,
    pub failed_agents: u64,
    pub history: History,
    pub collector_errors: u64,
}

pub fn aggregate(store: &Store, now: DateTime<Utc>, budget: f64) -> Result<State> {
    let date = now.with_timezone(&Local).date_naive();
    let midnight = local_midnight(date)?;
    let tomorrow = local_midnight(date.succ_opt().ok_or("Date is out of range")?)?;
    aggregate_between(store, now.timestamp(), midnight, tomorrow, budget)
}

fn local_midnight(date: NaiveDate) -> Result<i64> {
    Ok(Local
        .from_local_datetime(&date.and_time(NaiveTime::MIN))
        .earliest()
        .ok_or("Invalid local midnight")?
        .timestamp())
}

pub fn aggregate_between(
    store: &Store,
    now: i64,
    midnight: i64,
    tomorrow: i64,
    budget: f64,
) -> Result<State> {
    if !budget.is_finite() || budget <= 0. {
        return Err("Budget must be positive and finite".into());
    }
    let mut state = State {
        schema_version: 1,
        generated_at: now,
        ..State::default()
    };
    let db = &store.db;
    state.last_event_at = db.query_row(
        "SELECT MAX(timestamp) FROM events WHERE timestamp<=?",
        [now],
        |row| row.get(0),
    )?;
    state.has_usage = state.last_event_at.is_some();
    state.today = read_today(db, now, midnight, tomorrow, budget)?;
    state.providers = read_providers(db, now, midnight, state.today.spend_usd)?;
    state.agents = read_agents(db, now, midnight)?;
    state.active_agents = state
        .agents
        .iter()
        .filter(|a| a.status == AgentStatus::Running)
        .count() as u64;
    state.waiting_agents = state
        .agents
        .iter()
        .filter(|a| a.status == AgentStatus::Waiting)
        .count() as u64;
    state.failed_agents = state
        .agents
        .iter()
        .filter(|a| a.status == AgentStatus::Failed)
        .count() as u64;
    for provider in &mut state.providers {
        provider.agent_count = state
            .agents
            .iter()
            .filter(|a| {
                a.provider == provider.name
                    && matches!(a.status, AgentStatus::Running | AgentStatus::Waiting)
            })
            .count() as u64;
    }
    state.history = read_history(db, now)?;
    Ok(state)
}

fn read_today(
    db: &rusqlite::Connection,
    now: i64,
    midnight: i64,
    tomorrow: i64,
    budget: f64,
) -> Result<Today> {
    let mut today = db.query_row(
        "SELECT COALESCE(SUM(cost),0), COALESCE(SUM(input),0), COALESCE(SUM(output),0),
                COALESCE(SUM(cache_read+cache_write+cache_write_1h),0),
                COUNT(CASE WHEN cost IS NULL THEN 1 END)
         FROM events WHERE timestamp>=?1 AND timestamp<=?2",
        [midnight, now],
        |row| {
            Ok(Today {
                spend_usd: row.get(0)?,
                tokens_input: row.get::<_, i64>(1)? as u64,
                tokens_output: row.get::<_, i64>(2)? as u64,
                tokens_cache: row.get::<_, i64>(3)? as u64,
                unpriced_events: row.get::<_, i64>(4)? as u64,
                ..Today::default()
            })
        },
    )?;
    today.budget_usd = budget;
    today.budget_fraction = (today.spend_usd / budget).max(0.);
    today.budget_state = if today.budget_fraction > 1. {
        BudgetState::Exceeded
    } else if today.budget_fraction >= 0.9 {
        BudgetState::Warning
    } else if today.budget_fraction >= 0.7 {
        BudgetState::Elevated
    } else {
        BudgetState::Normal
    };
    today.tokens_total = today.tokens_input + today.tokens_output + today.tokens_cache;
    let (recent, samples, first): (f64, i64, Option<i64>) = db.query_row(
        "SELECT COALESCE(SUM(cost),0), COUNT(cost), MIN(timestamp)
         FROM events WHERE timestamp>?1 AND timestamp<=?2",
        [now - 1800, now],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    )?;
    today.burn_rate_per_hour = recent * 2.;
    if samples >= 2
        && first.is_some_and(|timestamp| now - timestamp >= 300)
        && today.unpriced_events == 0
    {
        today.projected_daily_spend = Some(
            today.spend_usd + today.burn_rate_per_hour * (tomorrow - now).max(0) as f64 / 3600.,
        );
    }
    Ok(today)
}

fn read_providers(
    db: &rusqlite::Connection,
    now: i64,
    midnight: i64,
    spend_usd: f64,
) -> Result<Vec<Provider>> {
    let mut query = db.prepare(
        "SELECT provider, COALESCE(SUM(cost),0),
                SUM(input+output+cache_read+cache_write+cache_write_1h)
         FROM events WHERE timestamp>=?1 AND timestamp<=?2
         GROUP BY provider ORDER BY provider",
    )?;
    let mut providers: Vec<Provider> = query
        .query_map([midnight, now], |row| {
            Ok(Provider {
                name: row.get(0)?,
                spend_usd: row.get(1)?,
                tokens: row.get::<_, i64>(2)? as u64,
                fraction: 0.,
                agent_count: 0,
            })
        })?
        .collect::<std::result::Result<_, _>>()?;
    for name in [ProviderKind::Claude, ProviderKind::Codex] {
        if !providers.iter().any(|p| p.name == name) {
            providers.push(Provider {
                name,
                ..Provider::default()
            });
        }
    }
    providers.sort_by_key(|provider| provider.name);
    for p in &mut providers {
        p.fraction = if spend_usd > 0. {
            p.spend_usd / spend_usd
        } else {
            0.
        };
    }
    Ok(providers)
}

fn read_agents(db: &rusqlite::Connection, now: i64, midnight: i64) -> Result<Vec<Agent>> {
    let mut query = db.prepare(
        "SELECT a.id, a.name, a.provider, a.status, a.started, a.updated,
                COALESCE(SUM(e.input+e.output+e.cache_read+e.cache_write+e.cache_write_1h),0),
                COALESCE(SUM(e.cost),0)
         FROM agents a LEFT JOIN events e ON e.agent=a.session AND e.provider=a.provider
         WHERE a.updated>=?1 AND a.updated<=?2 GROUP BY a.id ORDER BY a.updated DESC LIMIT 200",
    )?;
    let mut agents: Vec<Agent> = query
        .query_map([midnight.min(now - 86400), now], |row| {
            let stored_status: AgentStatus = row.get(3)?;
            let updated: i64 = row.get(5)?;
            let provider: ProviderKind = row.get(2)?;
            let status = stored_status.at(provider, now - updated);
            Ok(Agent {
                id: row.get(0)?,
                name: row.get(1)?,
                provider,
                status,
                last_activity_at: Some(updated),
                tokens: row.get::<_, i64>(6)? as u64,
                spend_usd: row.get(7)?,
            })
        })?
        .collect::<std::result::Result<_, _>>()?;
    agents.sort_by_key(|a| a.status.display_order());
    Ok(agents)
}

fn read_history(db: &rusqlite::Connection, now: i64) -> Result<History> {
    let start = now / 3600 * 3600 - 11 * 3600;
    let mut history = History {
        hourly_spend: vec![0.; 12],
    };
    let mut query = db.prepare(
        "SELECT (timestamp-?1)/3600, COALESCE(SUM(cost),0)
         FROM events WHERE timestamp>=?1 AND timestamp<=?2 GROUP BY 1",
    )?;
    for row in query.query_map([start, now], |row| {
        Ok((row.get::<_, i64>(0)?, row.get::<_, f64>(1)?))
    })? {
        let (i, v) = row?;
        if (0..12).contains(&i) {
            history.hourly_spend[i as usize] = v;
        }
    }
    Ok(history)
}
