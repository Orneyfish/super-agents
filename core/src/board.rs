//! The ticket board (specs/tickets/BOARD.md), ticket folders and their RD.md status lines.

use regex::Regex;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

/// Lowercase hex sha256 of a file's bytes: the content of `.evals.sha256` (plus a newline there).
pub fn fingerprint(file: &Path) -> io::Result<String> {
    let digest = Sha256::digest(fs::read(file)?);
    Ok(format!("{digest:x}"))
}

pub const STATUSES: [&str; 4] = ["draft", "ready", "building", "done"];
/// STATUSES as board.py printed them (a Python tuple), so messages stay the same.
pub const STATUSES_TEXT: &str = "('draft', 'ready', 'building', 'done')";

static ROW: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^\|\s*(\d{3})\s*\|\s*(.*?)\s*\|\s*(\w+)\s*\|\s*(\w+)\s*\|\s*(.*?)\s*\|\s*$")
        .expect("row regex")
});
static STATUS_WORD: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?m)^\*\*Status:\*\*\s*(\w+)").expect("status word regex"));
static THREE_DIGITS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\d{3}").expect("digits regex"));

/// One `| NNN | Title | Status | Mode | Runs |` row of BOARD.md (the title is not needed).
#[derive(Debug)]
pub struct Row {
    pub id: String,
    pub status: String,
    pub mode: String,
    pub runs: String,
}

pub fn board_path(root: &Path) -> PathBuf {
    root.join("specs").join("tickets").join("BOARD.md")
}

pub fn parse_rows(text: &str) -> Vec<Row> {
    text.lines()
        .filter_map(|line| ROW.captures(line))
        .map(|c| Row {
            id: c[1].to_string(),
            status: c[3].to_string(),
            mode: c[4].to_string(),
            runs: c[5].to_string(),
        })
        .collect()
}

/// The single `specs/tickets/NNN-*` entry for a ticket number; None when there are none or several.
pub fn ticket_dir(root: &Path, nnn: &str) -> Option<PathBuf> {
    let prefix = format!("{nnn}-");
    let mut hits = fs::read_dir(root.join("specs").join("tickets"))
        .ok()?
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with(&prefix))
        .map(|e| e.path());
    let first = hits.next()?;
    hits.next().is_none().then_some(first)
}

/// The first `**Status:** <word>` in a folder's RD.md.
pub fn rd_status(dir: &Path) -> Option<String> {
    let text = fs::read_to_string(dir.join("RD.md")).ok()?;
    STATUS_WORD.captures(&text).map(|c| c[1].to_string())
}

/// Ticket numbers in a `waits for NNN, NNN: why` Runs cell (the part before the first colon).
fn deps(row: &Row) -> Vec<String> {
    if !row.runs.starts_with("waits for") {
        return Vec::new();
    }
    let head = row.runs.split(':').next().unwrap_or_default();
    THREE_DIGITS
        .find_iter(head)
        .map(|m| m.as_str().to_string())
        .collect()
}

/// `NNN-…`: three ASCII digits and a dash.
fn is_ticket_name(name: &str) -> bool {
    let b = name.as_bytes();
    b.len() >= 4 && b[..3].iter().all(u8::is_ascii_digit) && b[3] == b'-'
}

/// Names of the `specs/tickets/NNN-*` entries, sorted (deviation D1).
fn ticket_folders(root: &Path) -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(root.join("specs").join("tickets"))
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| is_ticket_name(n))
        .collect();
    names.sort();
    names
}

/// Every dependency cycle as "a -> b -> a", found and ordered the way board.py did.
pub fn cycles(rows: &[Row]) -> Vec<String> {
    let mut order: Vec<&str> = Vec::new();
    let mut graph: HashMap<&str, Vec<String>> = HashMap::new();
    for r in rows {
        if !graph.contains_key(r.id.as_str()) {
            order.push(&r.id);
        }
        graph.insert(&r.id, deps(r));
    }
    let mut out = Vec::new();
    let mut seen: HashSet<&str> = HashSet::new();
    for n in &order {
        walk(n, &mut Vec::new(), &graph, &mut seen, &mut out);
    }
    out
}

fn walk<'a>(
    n: &'a str,
    path: &mut Vec<&'a str>,
    graph: &'a HashMap<&'a str, Vec<String>>,
    seen: &mut HashSet<&'a str>,
    out: &mut Vec<String>,
) {
    if let Some(i) = path.iter().position(|p| *p == n) {
        let mut cycle = path[i..].to_vec();
        cycle.push(n);
        out.push(cycle.join(" -> "));
        return;
    }
    if seen.contains(n) || !graph.contains_key(n) {
        return;
    }
    seen.insert(n);
    path.push(n);
    for d in &graph[n] {
        walk(d, path, graph, seen, out);
    }
    path.pop();
}

/// `board check`: the report to print, and whether the board is consistent.
pub fn check(root: &Path) -> (String, bool) {
    let mut bad: Vec<String> = Vec::new();
    let text = match fs::read_to_string(board_path(root)) {
        Ok(text) => text,
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            bad.push("no specs/tickets/BOARD.md".to_string());
            String::new()
        }
        Err(e) => {
            bad.push(format!("cannot read specs/tickets/BOARD.md: {e}"));
            String::new()
        }
    };
    let rows = parse_rows(&text);
    let ids: Vec<&str> = rows.iter().map(|r| r.id.as_str()).collect();
    let mut counts: BTreeMap<&str, usize> = BTreeMap::new();
    for &id in &ids {
        *counts.entry(id).or_default() += 1;
    }
    bad.extend(
        counts
            .iter()
            .filter(|(_, n)| **n > 1)
            .map(|(id, _)| format!("duplicate id {id}")),
    );
    for r in &rows {
        let id = &r.id;
        if !STATUSES.contains(&r.status.as_str()) {
            bad.push(format!(
                "{id}: status '{}' is not one of {STATUSES_TEXT}",
                r.status
            ));
        }
        if r.mode != "solo" && r.mode != "team" {
            bad.push(format!("{id}: mode must be solo or team"));
        }
        if r.runs != "alongside" && !r.runs.starts_with("waits for") {
            bad.push(format!(
                "{id}: Runs must be 'alongside' or 'waits for NNN: why'"
            ));
        }
        let Some(dir) = ticket_dir(root, id) else {
            bad.push(format!("{id}: no folder specs/tickets/{id}-*"));
            continue;
        };
        let status = rd_status(&dir);
        if status.as_deref() != Some(r.status.as_str()) {
            bad.push(format!(
                "{id}: RD.md Status is '{}', board says '{}'",
                status.as_deref().unwrap_or("None"),
                r.status
            ));
        }
        for dep in deps(r) {
            if !ids.contains(&dep.as_str()) {
                bad.push(format!("{id}: waits for {dep}, which is not on the board"));
            }
        }
    }
    for name in ticket_folders(root) {
        if !ids.contains(&&name[..3]) {
            bad.push(format!("{name} has no board row"));
        }
    }
    bad.extend(
        cycles(&rows)
            .into_iter()
            .map(|c| format!("dependency cycle {c}")),
    );
    if bad.is_empty() {
        (format!("OK: board ({} tickets)", rows.len()), true)
    } else {
        (
            bad.iter()
                .map(|b| format!("FAIL: {b}"))
                .collect::<Vec<_>>()
                .join("\n"),
            false,
        )
    }
}
