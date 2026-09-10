# Pricing assumptions

Rates were checked against the official [OpenAI API pricing](https://developers.openai.com/api/docs/pricing), [GPT-5.4 model page](https://developers.openai.com/api/docs/models/gpt-5.4), [Codex rate card](https://help.openai.com/en/articles/20001415), and [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing) on September 10, 2026. The table in `rust/src/telemetry.rs` is deliberately small and exact-match based. Dated Claude model IDs are supported without guessing prices for future versions.

Cats estimates standard API token spend in USD. It does not infer subscription charges, prepaid credits, billing discounts, provider quota, taxes, tool charges, regional pricing, fast/priority tiers, or long-context premiums from logs that may omit these fields. Treat the estimate as a comparison signal. Unknown models have a null internal cost and a visible partial-estimate indicator; their tokens still count.

Claude cache creation tokens are separate from regular input. Explicit one-hour writes use twice the base input rate; other creation tokens use the five-minute multiplier of 1.25. Cache hits use the model's cache-read rate. Codex input includes cached input and cache writes, so these are subtracted before pricing uncached input. Reasoning output is a subset of output and is not billed twice.

Historical events currently use the bundled rate table at first ingestion. This is not a versioned historical invoice engine. Changing rates does not rewrite already recorded costs. OpenAI long-context and service-tier surcharges are not implemented in V1; the interface labels every amount as an estimate.
