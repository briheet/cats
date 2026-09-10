use crate::{
    Result,
    storage::Store,
    telemetry::{Tokens, label},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

mod parsers;
pub use parsers::parse;

const MAX_LINE_BYTES: usize = 1_048_576;
const MAX_BATCH_BYTES: usize = 4 * MAX_LINE_BYTES;
use std::{
    fs::{self, File},
    io::{BufRead, BufReader, Read, Seek, SeekFrom},
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
};

#[derive(Clone, Default, Debug, Deserialize, Serialize)]
pub struct Cursor {
    pub offset: u64,
    pub inode: u64,
    pub session: String,
    pub model: String,
    pub name: String,
    pub total: Tokens,
    pub started: i64,
    pub updated: i64,
    pub status: String,
    pub skipping: bool,
}

pub fn files(root: &Path) -> std::io::Result<Vec<PathBuf>> {
    let mut result = Vec::new();
    let mut dirs = vec![root.to_path_buf()];
    while let Some(dir) = dirs.pop() {
        let entries = match fs::read_dir(dir) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error),
        };
        for entry in entries {
            let entry = entry?;
            let kind = match entry.file_type() {
                Ok(kind) => kind,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error),
            };
            if kind.is_dir() {
                dirs.push(entry.path());
            } else if kind.is_file() && entry.path().extension().is_some_and(|x| x == "jsonl") {
                result.push(entry.path());
            }
        }
    }
    result.sort();
    Ok(result)
}

#[derive(Debug, Default)]
pub struct Batch {
    pub events: usize,
    pub more: bool,
}

pub fn ingest(store: &mut Store, path: &Path, provider: &str) -> Result<Batch> {
    let file = File::open(path)?;
    let metadata = file.metadata()?;
    let key = path.to_string_lossy();
    let mut cursor = store.cursor(&key)?;
    if cursor.inode != metadata.ino() || metadata.len() < cursor.offset {
        cursor = Cursor::default();
    }
    cursor.inode = metadata.ino();
    if cursor.offset == metadata.len() {
        return Ok(Batch::default());
    }
    if cursor.session.is_empty() {
        cursor.session = label(
            path.file_stem()
                .and_then(|x| x.to_str())
                .unwrap_or("session"),
        );
    }
    let mut reader = BufReader::new(file);
    reader.seek(SeekFrom::Start(cursor.offset))?;
    let tx = store.db.transaction()?;
    let mut count = 0;
    let mut bytes = 0;
    // Bound memory even when logs contain enormous prompts or malformed lines.
    while bytes < MAX_BATCH_BYTES {
        let mut line = Vec::new();
        let read = reader
            .by_ref()
            .take(MAX_LINE_BYTES as u64)
            .read_until(b'\n', &mut line)?;
        if read == 0 {
            break;
        }
        let complete = line.last() == Some(&b'\n');
        if !complete && read < MAX_LINE_BYTES {
            break;
        } // retry a partially appended line later
        cursor.offset += read as u64;
        bytes += read;
        if !complete {
            cursor.skipping = true;
            continue;
        }
        if cursor.skipping {
            cursor.skipping = false;
            continue;
        }
        match serde_json::from_slice::<Value>(&line) {
            Ok(v) => {
                if let Some(e) = parse(&v, provider, &mut cursor) {
                    count += Store::insert(&tx, &e)?;
                }
            }
            Err(_) => tracing::warn!(collector = provider, "Skipped malformed telemetry record"),
        }
    }
    Store::save_cursor(&tx, &key, provider, &cursor)?;
    tx.commit()?;
    Ok(Batch {
        events: count,
        more: bytes >= MAX_BATCH_BYTES && cursor.offset < metadata.len(),
    })
}
