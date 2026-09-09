use crate::{Result, storage::Store};
use chrono::{DateTime, Local, TimeZone, Utc};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Today {
    pub spend_usd: f64,
    pub budget_usd: f64,
    pub budget_fraction: f64,
    pub budget_state: String,
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
    pub name: String,
    pub spend_usd: f64,
    pub tokens: u64,
    pub fraction: f64,
    #[serde(default)]
    pub agent_count: u64,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Agent {
    pub id: String,
    pub name: String,
    pub provider: String,
    pub status: String,
    pub elapsed_seconds: i64,
    pub tokens: u64,
    pub spend_usd: f64,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct History {
    pub hourly_spend: Vec<f64>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct State {
    #[serde(default)]
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
    let local = now.with_timezone(&Local);
    let midnight = Local
        .from_local_datetime(&local.date_naive().and_hms_opt(0, 0, 0).unwrap())
        .earliest()
        .ok_or("Invalid local midnight")?
        .timestamp();
    let tomorrow = Local
        .from_local_datetime(
            &local
                .date_naive()
                .succ_opt()
                .unwrap()
                .and_hms_opt(0, 0, 0)
                .unwrap(),
        )
        .earliest()
        .ok_or("Invalid next midnight")?
        .timestamp();
    aggregate_between(store, now.timestamp(), midnight, tomorrow, budget)
}
pub fn aggregate_between(
    store: &Store,
    now: i64,
    midnight: i64,
    tomorrow: i64,
    budget: f64,
) -> Result<State> {
    let mut s = State {
        schema_version: 1,
        generated_at: now,
        ..State::default()
    };
    let db = &store.db;
    s.last_event_at = db.query_row(
        "SELECT MAX(timestamp) FROM events WHERE timestamp<=?",
        [now],
        |r| r.get(0),
    )?;
    s.has_usage = s.last_event_at.is_some();
    s.today = db.query_row("SELECT COALESCE(SUM(cost),0), COALESCE(SUM(input),0), COALESCE(SUM(output),0), COALESCE(SUM(cache_read+cache_write+cache_write_1h),0), COUNT(CASE WHEN cost IS NULL THEN 1 END) FROM events WHERE timestamp>=?1 AND timestamp<=?2", [midnight, now], |r| {
        Ok(Today { spend_usd: r.get(0)?, tokens_input: r.get::<_,i64>(1)? as u64, tokens_output: r.get::<_,i64>(2)? as u64, tokens_cache: r.get::<_,i64>(3)? as u64, unpriced_events: r.get::<_,i64>(4)? as u64, ..Today::default() })
    })?;
    let t = &mut s.today;
    t.budget_usd = budget;
    t.budget_fraction = (t.spend_usd / budget).max(0.);
    t.budget_state = if t.budget_fraction > 1. {
        "exceeded"
    } else if t.budget_fraction >= 0.9 {
        "warning"
    } else if t.budget_fraction >= 0.7 {
        "elevated"
    } else {
        "normal"
    }
    .into();
    t.tokens_total = t.tokens_input + t.tokens_output + t.tokens_cache;
    let (recent, samples, first): (f64, i64, Option<i64>) = db.query_row("SELECT COALESCE(SUM(cost),0), COUNT(cost), MIN(timestamp) FROM events WHERE timestamp>?1 AND timestamp<=?2", [now - 1800, now], |r| Ok((r.get(0)?,r.get(1)?,r.get(2)?)))?;
    t.burn_rate_per_hour = recent * 2.;
    if samples >= 2 && first.is_some_and(|x| now - x >= 300) && t.unpriced_events == 0 {
        t.projected_daily_spend =
            Some(t.spend_usd + t.burn_rate_per_hour * (tomorrow - now).max(0) as f64 / 3600.);
    }
    let mut query = db.prepare("SELECT provider, COALESCE(SUM(cost),0), SUM(input+output+cache_read+cache_write+cache_write_1h) FROM events WHERE timestamp>=?1 AND timestamp<=?2 GROUP BY provider ORDER BY provider")?;
    s.providers = query
        .query_map([midnight, now], |r| {
            Ok(Provider {
                name: r.get(0)?,
                spend_usd: r.get(1)?,
                tokens: r.get::<_, i64>(2)? as u64,
                fraction: 0.,
                agent_count: 0,
            })
        })?
        .collect::<std::result::Result<_, _>>()?;
    for name in ["Claude", "Codex"] {
        if !s.providers.iter().any(|p| p.name == name) {
            s.providers.push(Provider {
                name: name.into(),
                ..Provider::default()
            });
        }
    }
    s.providers.sort_by(|a, b| a.name.cmp(&b.name));
    for p in &mut s.providers {
        p.fraction = if t.spend_usd > 0. {
            p.spend_usd / t.spend_usd
        } else {
            0.
        };
    }
    let mut query = db.prepare("SELECT a.id,a.name,a.provider,a.status,a.started,a.updated, COALESCE(SUM(e.input+e.output+e.cache_read+e.cache_write+e.cache_write_1h),0),COALESCE(SUM(e.cost),0) FROM agents a LEFT JOIN events e ON e.agent=a.session AND e.provider=a.provider WHERE a.updated>=?1 GROUP BY a.id ORDER BY a.updated DESC LIMIT 200")?;
    s.agents = query
        .query_map([midnight.min(now - 86400)], |r| {
            let mut status: String = r.get(3)?;
            let started: i64 = r.get(4)?;
            let updated: i64 = r.get(5)?;
            // Silence is not proof of completion; surface it as waiting.
            if status == "running" && now - updated > 300 {
                status = "waiting".into();
            }
            let end = if status == "running" { now } else { updated };
            Ok(Agent {
                id: r.get(0)?,
                name: r.get(1)?,
                provider: r.get(2)?,
                status,
                elapsed_seconds: (end - started).max(0),
                tokens: r.get::<_, i64>(6)? as u64,
                spend_usd: r.get(7)?,
            })
        })?
        .collect::<std::result::Result<_, _>>()?;
    s.agents.sort_by_key(|a| match a.status.as_str() {
        "running" => 0,
        "waiting" => 1,
        "failed" => 2,
        _ => 3,
    });
    s.active_agents = s.agents.iter().filter(|a| a.status == "running").count() as u64;
    s.waiting_agents = s.agents.iter().filter(|a| a.status == "waiting").count() as u64;
    s.failed_agents = s.agents.iter().filter(|a| a.status == "failed").count() as u64;
    for provider in &mut s.providers {
        provider.agent_count = s
            .agents
            .iter()
            .filter(|a| {
                a.provider == provider.name && matches!(a.status.as_str(), "running" | "waiting")
            })
            .count() as u64;
    }
    let start = now / 3600 * 3600 - 11 * 3600;
    s.history.hourly_spend = vec![0.; 12];
    let mut query = db.prepare("SELECT (timestamp-?1)/3600,COALESCE(SUM(cost),0) FROM events WHERE timestamp>=?1 AND timestamp<=?2 GROUP BY 1")?;
    for row in query.query_map([start, now], |r| {
        Ok((r.get::<_, i64>(0)?, r.get::<_, f64>(1)?))
    })? {
        let (i, v) = row?;
        if (0..12).contains(&i) {
            s.history.hourly_spend[i as usize] = v;
        }
    }
    Ok(s)
}
