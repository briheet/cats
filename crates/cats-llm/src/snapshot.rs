use crate::{Result, aggregation::State};
pub use cats_core::atomic_write;
use std::{fs, path::Path};
pub fn write(dir: &Path, state: &State) -> Result<bool> {
    let path = dir.join("state.json");
    if let Ok(bytes) = fs::read(&path)
        && let Ok(mut old) = serde_json::from_slice::<State>(&bytes)
    {
        old.generated_at = state.generated_at;
        if old == *state {
            return Ok(false);
        }
    }
    atomic_write(&path, &serde_json::to_vec(state)?)?;
    Ok(true)
}
