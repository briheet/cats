use crate::{Result, aggregation::State};
use std::{
    fs::{self, OpenOptions},
    io::Write,
    os::unix::fs::OpenOptionsExt,
    path::Path,
};

pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let tmp = path.with_extension(format!("{}.tmp", std::process::id()));
    let result = (|| {
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .open(&tmp)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&tmp, path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(tmp);
    }
    result
}
pub fn write(dir: &Path, state: &State) -> Result<bool> {
    let path = dir.join("cats-state.json");
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
