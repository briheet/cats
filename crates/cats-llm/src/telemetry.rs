use crate::domain::ProviderKind;
use serde::{Deserialize, Serialize};
use serde_json::Value;

// Input is uncached input. Cache reads and writes are disjoint token buckets.
#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct Tokens {
    pub input: u64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_write: u64,
    pub cache_write_1h: u64,
}
impl Tokens {
    pub fn total(self) -> u64 {
        self.input + self.output + self.cache_read + self.cache_write + self.cache_write_1h
    }
    pub fn delta(self, old: Self) -> Self {
        Self {
            input: self.input.saturating_sub(old.input),
            output: self.output.saturating_sub(old.output),
            cache_read: self.cache_read.saturating_sub(old.cache_read),
            cache_write: self.cache_write.saturating_sub(old.cache_write),
            cache_write_1h: self.cache_write_1h.saturating_sub(old.cache_write_1h),
        }
    }
    pub fn codex(v: &Value) -> Self {
        let read = number(v, "cached_input_tokens").min(number(v, "input_tokens"));
        let write = number(v, "cache_write_input_tokens")
            .min(number(v, "input_tokens").saturating_sub(read));
        Self {
            input: number(v, "input_tokens").saturating_sub(read + write),
            output: number(v, "output_tokens"),
            cache_read: read,
            cache_write: write,
            cache_write_1h: 0,
        }
    }
    pub fn claude(v: &Value) -> Self {
        let hour = number(&v["cache_creation"], "ephemeral_1h_input_tokens");
        Self {
            input: number(v, "input_tokens"),
            output: number(v, "output_tokens"),
            cache_read: number(v, "cache_read_input_tokens"),
            cache_write: number(v, "cache_creation_input_tokens").saturating_sub(hour),
            cache_write_1h: hour,
        }
    }
}
pub fn number(v: &Value, key: &str) -> u64 {
    v[key].as_u64().unwrap_or(0).min(1_000_000_000_000)
}
pub fn label(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).take(100).collect()
}

#[derive(Clone, Debug)]
pub struct Event {
    pub id: String,
    pub timestamp: i64,
    pub provider: ProviderKind,
    pub model: String,
    pub session: String,
    pub agent: String,
    pub tokens: Tokens,
    pub cost: Option<f64>,
}

// Standard API-equivalent USD per million tokens, checked 2026-09-10.
// Unknown models are deliberately unpriced. See docs/pricing.md.
pub fn price(model: &str, t: Tokens) -> Option<f64> {
    let model = model.to_lowercase();
    let (input, output, cache): (f64, f64, f64) = match model.as_str() {
        "gpt-6-astra" => (10., 50., 1.),
        "gpt-5.6-sol" => (4., 20., 0.4),
        "gpt-5.6-terra" => (2., 12., 0.2),
        "gpt-5.6-luna" => (0.2, 1.2, 0.02),
        "gpt-5.4" => (2.5, 15., 0.25),
        "gpt-5.3-codex" => (1.75, 14., 0.175),
        s if model_is(s, "claude-sonnet-5") => (2., 10., 0.2),
        s if ["claude-sonnet-4-6", "claude-sonnet-4-5", "claude-sonnet-4"]
            .iter()
            .any(|m| model_is(s, m)) =>
        {
            (3., 15., 0.3)
        }
        s if [
            "claude-opus-5",
            "claude-opus-4-8",
            "claude-opus-4-7",
            "claude-opus-4-6",
            "claude-opus-4-5",
        ]
        .iter()
        .any(|m| model_is(s, m)) =>
        {
            (5., 25., 0.5)
        }
        s if model_is(s, "claude-haiku-4-5") => (1., 5., 0.1),
        _ => return None,
    };
    Some(
        (t.input as f64 * input
            + t.output as f64 * output
            + t.cache_read as f64 * cache
            + t.cache_write as f64 * input * 1.25
            + t.cache_write_1h as f64 * input * 2.)
            / 1_000_000.,
    )
}
fn model_is(model: &str, base: &str) -> bool {
    model == base
        || model.strip_prefix(base).is_some_and(|s| {
            s.len() == 9 && s.starts_with('-') && s[1..].bytes().all(|c| c.is_ascii_digit())
        })
}
