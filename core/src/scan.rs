//! `board scan`: one PROBLEM line per thing the watchdog should look at; no output means healthy.
//! Same checks, messages and order as board.py, including how it treats bad input: a status file
//! that is not a JSON object is reported while any ticket is building, a heartbeat field that is
//! missing or unusable is reported without hiding the other heartbeats, and a watchdog.conf limit
//! that is not a finite number falls back to its default. Heartbeat files are read in sorted order
//! (deviation D1), and the reason after "unreadable:" is sa-core's own wording (D2).

use crate::{board, http, isotime};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// One heartbeat file. A field that cannot be used keeps the reason as its error.
struct Job {
    file: String,
    who: String,
    phase: Result<String, String>,
    note: String,
    updated: Result<f64, String>,
    started: Result<f64, String>,
}

/// The watchdog's limits in minutes.
struct Limits {
    stale: f64,
    wait: f64,
    slow: f64,
}

pub fn scan(root: &Path) -> Vec<String> {
    let conf = read_conf(root);
    let limits = Limits {
        stale: limit(&conf, "stale_min", 15.0),
        wait: limit(&conf, "wait_min", 45.0),
        slow: limit(&conf, "slow_min", 60.0),
    };
    let skip: HashSet<&str> = conf
        .get("ignore")
        .map(String::as_str)
        .unwrap_or("")
        .split(',')
        .map(str::trim)
        .filter(|x| !x.is_empty())
        .collect();
    let now = isotime::now_unix();

    let mut jobs: HashMap<String, Vec<Job>> = HashMap::new();
    let mut unreadable = Vec::new();
    for path in status_files(root) {
        let file = path
            .strip_prefix(root)
            .unwrap_or(&path)
            .display()
            .to_string();
        match load_job(&path, &file) {
            Ok((Some(ticket), job)) => jobs.entry(ticket).or_default().push(job),
            Ok((None, _)) => {}
            Err(e) => unreadable.push(format!("PROBLEM {file} unreadable: {e}")),
        }
    }

    let rows = board::rows(root);
    let building: Vec<&board::Row> = rows
        .iter()
        .filter(|r| r.status == "building" && !skip.contains(r.id.as_str()))
        .collect();
    let mut out = Vec::new();
    if !building.is_empty() {
        // a file that is not JSON names no ticket, so it only matters while something is building
        out.extend(unreadable);
    }
    for row in building {
        match jobs.get(&row.id) {
            None => out.push(format!(
                "PROBLEM {} is 'building' but has no status file: the worker never started or died",
                row.id
            )),
            Some(js) => job_problems(&row.id, js, &limits, now, &mut out),
        }
    }
    out.extend(
        board::cycles(&rows)
            .into_iter()
            .map(|c| format!("PROBLEM dependency cycle {c}")),
    );
    if let Some(url) = conf.get("app_url").filter(|u| !u.is_empty()) {
        if let Err(e) = http::probe(url, Duration::from_secs(5)) {
            out.push(format!("PROBLEM main app not answering at {url}: {e}"));
        }
    }
    out
}

/// The problems of one building ticket's heartbeats, checked field by field in board.py's order.
fn job_problems(id: &str, js: &[Job], limits: &Limits, now: f64, out: &mut Vec<String>) {
    let mut started: Vec<(bool, f64)> = Vec::new(); // (still working, minutes since it started)
    for j in js {
        let unreadable = |e: &str| format!("PROBLEM {id} status file unreadable: {}: {e}", j.file);
        let phase = match &j.phase {
            Ok(phase) => phase.as_str(),
            Err(e) => {
                out.push(unreadable(e));
                continue;
            }
        };
        if phase == "blocked" {
            out.push(format!(
                "PROBLEM {id} {} reports blocked: {}",
                j.who, j.note
            ));
        } else if phase == "waiting" {
            // it stopped to ask the user: not silent, and the router must hear the question
            out.push(format!(
                "PROBLEM {id} {} waits for the user: {}",
                j.who, j.note
            ));
        } else if phase != "done" {
            // testing/reviewing: the worker waits on its own tester or reviewer and cannot heartbeat
            let limit = if phase == "testing" || phase == "reviewing" {
                limits.wait
            } else {
                limits.stale
            };
            match &j.updated {
                Ok(t) => {
                    let m = (now - t) / 60.0;
                    if m > limit {
                        out.push(format!(
                            "PROBLEM {id} {} silent for {m:.0} min in phase '{phase}'",
                            j.who
                        ));
                    }
                }
                Err(e) => {
                    out.push(unreadable(e));
                    continue;
                }
            }
        }
        match &j.started {
            Ok(t) => started.push((phase != "done", (now - t) / 60.0)),
            Err(e) => out.push(unreadable(e)),
        }
    }
    if started.iter().any(|(working, _)| *working) {
        let longest = started
            .iter()
            .map(|(_, m)| *m)
            .fold(f64::NEG_INFINITY, f64::max);
        if longest > limits.slow {
            out.push(format!("PROBLEM {id} slow: building for {longest:.0} min"));
        }
    }
}

/// `.super-agents/watchdog.conf`: `key = value` lines; `#` starts a comment line.
fn read_conf(root: &Path) -> HashMap<String, String> {
    let mut conf = HashMap::new();
    if let Ok(text) = fs::read_to_string(root.join(".super-agents").join("watchdog.conf")) {
        for line in text.lines() {
            if line.trim_start().starts_with('#') {
                continue;
            }
            if let Some((k, v)) = line.split_once('=') {
                conf.insert(k.trim().to_string(), v.trim().to_string());
            }
        }
    }
    conf
}

/// A minutes limit from watchdog.conf, or its default when the value is not a finite number:
/// a typo must not silence the watchdog.
fn limit(conf: &HashMap<String, String>, key: &str, default: f64) -> f64 {
    conf.get(key)
        .and_then(|v| v.parse::<f64>().ok())
        .filter(|v| v.is_finite())
        .unwrap_or(default)
}

/// Heartbeat files: solo workers' `.claude/worktrees/*/.job/status*.json`, then team members' `.job/status-*.json`.
fn status_files(root: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    for worktree in entries(&root.join(".claude").join("worktrees")) {
        if name_of(&worktree).starts_with('.') {
            continue;
        }
        files.extend(entries(&worktree.join(".job")).into_iter().filter(|f| {
            let n = name_of(f);
            n.starts_with("status") && n.ends_with(".json")
        }));
    }
    files.extend(entries(&root.join(".job")).into_iter().filter(|f| {
        let n = name_of(f);
        n.starts_with("status-") && n.ends_with(".json")
    }));
    files
}

/// A directory's entries, sorted; none when it cannot be read.
fn entries(dir: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .collect();
    v.sort();
    v
}

fn name_of(p: &Path) -> String {
    p.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// A heartbeat file and the ticket it names; an error when it is not a readable JSON object.
fn load_job(path: &Path, file: &str) -> Result<(Option<String>, Job), String> {
    let text = fs::read_to_string(path).map_err(|e| e.to_string())?;
    let value: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let map = value.as_object().ok_or("not a JSON object")?;
    let text = |key: &str| match map.get(key) {
        None => Err(format!("missing '{key}'")),
        Some(serde_json::Value::String(s)) => Ok(s.clone()),
        Some(other) => Err(format!("'{key}' is {other}, not a string")),
    };
    let stamp = |key: &str| {
        text(key).and_then(|t| {
            isotime::parse_unix(&t).ok_or_else(|| format!("bad '{key}' timestamp '{t}'"))
        })
    };
    let job = Job {
        file: file.to_string(),
        who: text("agent")
            .ok()
            .filter(|a| !a.is_empty())
            .unwrap_or_else(|| "worker".to_string()),
        phase: text("phase"),
        note: text("note").unwrap_or_default(),
        updated: stamp("updated"),
        started: stamp("started"),
    };
    Ok((text("ticket").ok(), job))
}
