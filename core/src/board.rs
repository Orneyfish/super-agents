//! The ticket board (specs/tickets/BOARD.md), ticket folders and their RD.md status lines.

use regex::Regex;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

/// Lowercase hex sha256 of a file, with every CRLF read as LF: the content of `.evals.sha256` (plus a newline there).
/// The fingerprint is of what the user approved, not of how Git wrote it: with `core.autocrlf=true` (the Git for
/// Windows default) a worker's worktree is checked out with CRLF, and its evals.md must still match. A carriage
/// return that is not part of a CRLF is content and still counts.
pub fn fingerprint(file: &Path) -> io::Result<String> {
    Ok(format!("{:x}", Sha256::digest(lf_bytes(file)?)))
}

/// A file's bytes with every CRLF read as LF.
fn lf_bytes(file: &Path) -> io::Result<Vec<u8>> {
    let bytes = fs::read(file)?;
    let mut text = Vec::with_capacity(bytes.len());
    for (i, &b) in bytes.iter().enumerate() {
        if !(b == b'\r' && bytes.get(i + 1) == Some(&b'\n')) {
            text.push(b);
        }
    }
    Ok(text)
}

/// The fingerprint of an RD.md as the user approved it: like `fingerprint`, but without the first `**Status:**` line,
/// which `board set` rewrites on every status change. The second line of `.evals.sha256` (`<hex>  RD.md`).
pub fn fingerprint_rd(file: &Path) -> io::Result<String> {
    let bytes = lf_bytes(file)?;
    let text = String::from_utf8_lossy(&bytes);
    Ok(format!(
        "{:x}",
        Sha256::digest(STATUS_LINE.replace(&text, "").as_bytes())
    ))
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

/// The whole first `**Status:**` line, without its line ending (so CRLF files stay CRLF).
static STATUS_LINE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?m)^\*\*Status:\*\*[^\r\n]*").expect("status line regex"));

/// `board set`: RD.md's Status line, the fingerprints on `ready`, and the board row for a ticket folder.
pub fn set_status(root: &Path, target: &str, status: &str) -> Result<(), String> {
    if !STATUSES.contains(&status) {
        return Err(format!("status must be one of {STATUSES_TEXT}"));
    }
    let is_number = target.len() == 3 && target.bytes().all(|b| b.is_ascii_digit());
    let dir = if is_number {
        ticket_dir(root, target)
    } else {
        Some(PathBuf::from(target))
    };
    let dir = dir
        .filter(|d| d.is_dir())
        .ok_or_else(|| format!("no such ticket or directory: {target}"))?;
    // a ticket folder keeps its board row in sync, however it was named on the command line
    let number = ticket_number(&dir).or_else(|| is_number.then(|| target.to_string()));

    let rd = dir.join("RD.md");
    let text = fs::read_to_string(&rd).map_err(|e| format!("{}: {e}", rd.display()))?;
    let was = STATUS_WORD.captures(&text).map(|c| c[1].to_string());
    let line = format!("**Status:** {status}");
    let updated = if STATUS_LINE.is_match(&text) {
        STATUS_LINE
            .replace(&text, regex::NoExpand(line.as_str()))
            .into_owned()
    } else {
        let nl = if text.contains("\r\n") { "\r\n" } else { "\n" };
        text.replacen(nl, &format!("{nl}{nl}{line}{nl}"), 1)
    };
    write_atomic(&rd, &updated).map_err(|e| format!("{}: {e}", rd.display()))?;

    // The fingerprint of what the user approved; check-evals.sh --passed compares against it. It is written when a draft is
    // approved (or when there is none yet), not on every `ready`: setting an approved ticket `ready` again must not make
    // an edit made since look approved. Approving again goes through `draft`.
    let evals = dir.join("evals.md");
    let fp = dir.join(".evals.sha256");
    let approved = matches!(was.as_deref(), Some("ready" | "building" | "done")) && fp.exists();
    if status == "ready" && evals.exists() && !approved {
        let hex = fingerprint(&evals).map_err(|e| format!("{}: {e}", evals.display()))?;
        let rd_hex = fingerprint_rd(&rd).map_err(|e| format!("{}: {e}", rd.display()))?;
        // line 1 is all that older versions wrote and read; line 2 covers RD.md
        write_atomic(&fp, &format!("{hex}\n{rd_hex}  RD.md\n"))
            .map_err(|e| format!("{}: {e}", fp.display()))?;
    }

    let board = board_path(root);
    if let Some(number) = number.filter(|_| board.exists()) {
        set_board_row(&board, &number, status).map_err(|e| format!("{}: {e}", board.display()))?;
    }
    Ok(())
}

/// Replaces a file in one step, so a reader that takes no lock (the router's Read tool, check-evals, the scan) sees the
/// old content or the new, never an empty or half-written file: a temp file in the same folder, renamed over the target.
fn write_atomic(path: &Path, content: &str) -> io::Result<()> {
    let mut tmp = path.as_os_str().to_owned();
    tmp.push(format!(".tmp{}", std::process::id()));
    let tmp = PathBuf::from(tmp);
    fs::write(&tmp, content)?;
    for _ in 0..3 {
        if fs::rename(&tmp, path).is_ok() {
            return Ok(());
        }
        // Windows: the rename fails while another program holds the target open
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    let _ = fs::remove_file(&tmp);
    fs::write(path, content) // what this did before: not atomic, but the change is not lost
}

/// `NNN` when `dir` is a `specs/tickets/NNN-*` folder.
fn ticket_number(dir: &Path) -> Option<String> {
    let dir: PathBuf = dir.components().collect();
    let name = dir.file_name()?.to_str()?;
    let parent = dir.parent()?.file_name()?.to_str()?;
    (parent == "tickets" && is_ticket_name(name)).then(|| name[..3].to_string())
}

/// Rewrites the status cell of row `number` under an exclusive lock: several agents flip rows at once.
fn set_board_row(board: &Path, number: &str, status: &str) -> io::Result<()> {
    let mut file = OpenOptions::new().read(true).write(true).open(board)?;
    file.lock()?; // released when `file` is dropped
    let mut text = String::new();
    file.read_to_string(&mut text)?;
    let row = Regex::new(&format!(
        r"^(\|\s*{number}\s*\|.*?\|\s*)\w+(\s*\|\s*\w+\s*\|)"
    ))
    .map_err(io::Error::other)?;
    let replacement = format!("${{1}}{status}${{2}}");
    let updated: Vec<String> = text
        .split('\n')
        .map(|line| row.replace(line, replacement.as_str()).into_owned())
        .collect();
    file.seek(SeekFrom::Start(0))?;
    file.write_all(updated.join("\n").as_bytes())?;
    let end = file.stream_position()?;
    file.set_len(end)?;
    Ok(())
}

/// Rows of BOARD.md; none when it is missing or unreadable (`check` reports that, `scan` does not).
pub fn rows(root: &Path) -> Vec<Row> {
    fs::read_to_string(board_path(root))
        .map(|text| parse_rows(&text))
        .unwrap_or_default()
}
