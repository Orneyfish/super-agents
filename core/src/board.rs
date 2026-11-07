//! The ticket board (specs/tickets/BOARD.md), ticket folders and their RD.md status lines.

use sha2::{Digest, Sha256};
use std::fs;
use std::io;
use std::path::Path;

/// Lowercase hex sha256 of a file's bytes: the content of `.evals.sha256` (plus a newline there).
pub fn fingerprint(file: &Path) -> io::Result<String> {
    let digest = Sha256::digest(fs::read(file)?);
    Ok(format!("{digest:x}"))
}
