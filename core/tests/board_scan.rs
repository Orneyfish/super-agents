mod common;
use common::*;
use std::fs;
use std::path::Path;

/// `minutes` before the tests' fixed now (2026-11-07T10:15:00Z), as job-status.sh writes it.
fn ago(minutes: u64) -> String {
    let t = NOW - minutes * 60;
    let (h, m) = ((t % 86_400) / 3600, (t % 3600) / 60);
    format!("2026-11-07T{h:02}:{m:02}:00Z")
}

fn heartbeat(phase: &str, started: u64, updated: u64, note: &str) -> String {
    format!(
        r#"{{"ticket":"001","phase":"{phase}","started":"{}","updated":"{}","note":"{note}","agent":"a"}}"#,
        ago(started),
        ago(updated)
    )
}

fn job(root: &Path, file: &str, json: &str) {
    let p = root.join(file);
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(p, json).unwrap();
}

fn conf(root: &Path, text: &str) {
    fs::create_dir_all(root.join(".super-agents")).unwrap();
    fs::write(root.join(".super-agents/watchdog.conf"), text).unwrap();
}

fn set_building(root: &Path, id: &str) {
    assert_eq!(sa(root, &["board", "set", id, "building", s(root)]).code, 0);
}

fn scan(root: &Path) -> Run {
    sa(root, &["board", "scan", s(root)])
}

#[test]
fn a_building_ticket_without_a_heartbeat_is_reported() {
    let t = fixture();
    set_building(t.path(), "001");
    let r = scan(t.path());
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (
            0,
            "PROBLEM 001 is 'building' but has no status file: the worker never started or died\n"
        )
    );
}

#[test]
fn heartbeat_limits_follow_the_phase() {
    let t = fixture();
    let root = t.path();
    set_building(root, "001");
    let f = ".job/status-001-a.json";
    job(root, f, &heartbeat("testing", 3, 2, ""));
    assert_eq!(scan(root).stdout, "", "healthy");
    job(root, f, &heartbeat("building", 41, 40, ""));
    assert_eq!(
        scan(root).stdout,
        "PROBLEM 001 a silent for 40 min in phase 'building'\n"
    );
    job(root, f, &heartbeat("testing", 41, 40, ""));
    assert_eq!(
        scan(root).stdout,
        "",
        "testing/reviewing get wait_min (45), not stale_min (15)"
    );
    job(root, f, &heartbeat("reviewing", 51, 50, ""));
    assert_eq!(
        scan(root).stdout,
        "PROBLEM 001 a silent for 50 min in phase 'reviewing'\n"
    );
    job(root, f, &heartbeat("blocked", 2, 1, "db down"));
    assert_eq!(
        scan(root).stdout,
        "PROBLEM 001 a reports blocked: db down\n"
    );
    job(root, f, &heartbeat("building", 70, 2, ""));
    assert_eq!(scan(root).stdout, "PROBLEM 001 slow: building for 70 min\n");
    job(root, f, &heartbeat("done", 300, 200, ""));
    assert_eq!(scan(root).stdout, "", "a done job is never silent or slow");
}

#[test]
fn worktree_heartbeats_count_and_watchdog_conf_sets_limits_and_ignores() {
    let t = fixture();
    let root = t.path();
    set_building(root, "001");
    job(
        root,
        ".claude/worktrees/w1/.job/status.json",
        &heartbeat("building", 41, 40, ""),
    );
    assert_eq!(
        scan(root).stdout,
        "PROBLEM 001 a silent for 40 min in phase 'building'\n"
    );
    conf(root, "# limits\nstale_min = 50\n");
    assert_eq!(scan(root).stdout, "");
    conf(root, "ignore=001\nstale_min=5\n");
    assert_eq!(scan(root).stdout, "");
}

#[test]
fn a_dependency_cycle_is_reported() {
    let t = fixture();
    board(
        t.path(),
        &ROWS.replace("team | alongside", "team | waits for 002: x"),
    );
    assert_eq!(
        scan(t.path()).stdout,
        "PROBLEM dependency cycle 001 -> 002 -> 001\n"
    );
}

/// `.job/<name>` as scan prints it: relative to the root, with this platform's separator.
fn job_file(name: &str) -> String {
    Path::new(".job").join(name).display().to_string()
}

// Captured from board.py at 06e3e63 with the same files. It words the reason as a Python
// exception, JSONDecodeError(...) or AttributeError(...) (deviation D2).
#[test]
fn a_status_file_that_is_not_a_json_object_is_reported_while_something_is_building() {
    let t = fixture();
    let root = t.path();
    set_building(root, "001");
    job(root, ".job/status-001-a.json", "{not json");
    let out = scan(root).stdout;
    let lines: Vec<&str> = out.lines().collect();
    let prefix = format!("PROBLEM {} unreadable: ", job_file("status-001-a.json"));
    assert_eq!(lines.len(), 2, "{out}");
    assert!(lines[0].starts_with(&prefix), "{out}");
    assert_eq!(
        lines[1],
        "PROBLEM 001 is 'building' but has no status file: the worker never started or died"
    );
    job(root, ".job/status-001-a.json", r#"["not", "an", "object"]"#);
    assert!(scan(root)
        .stdout
        .starts_with(&format!("{prefix}not a JSON object\n")));
    conf(root, "ignore=001\n");
    assert_eq!(
        scan(root).stdout,
        "",
        "a broken file only matters while something is building"
    );
}

// Captured from board.py at 06e3e63 with the same files. It names no file and words the reason
// as a Python exception, KeyError('updated') or TypeError(...) (deviation D2).
#[test]
fn a_missing_or_bad_heartbeat_field_is_reported_without_hiding_the_others() {
    let t = fixture();
    let root = t.path();
    set_building(root, "001");
    set_building(root, "003");
    job(
        root,
        ".job/status-001-a.json",
        r#"{"ticket":"001","phase":"building","started":"2026-11-07T10:12:00Z","agent":"a"}"#,
    );
    job(
        root,
        ".job/status-001-b.json",
        r#"{"ticket":"001","phase":"building","started":"2026-11-07T10:00:00","updated":"2026-11-07T10:00:00","agent":"b"}"#,
    );
    job(
        root,
        ".job/status-001-c.json",
        r#"{"ticket":"001","phase":"blocked","updated":"2026-11-07T10:14:00Z","note":"db down","agent":"c"}"#,
    );
    job(
        root,
        ".job/status-001-d.json",
        r#"{"ticket":"001","started":"2026-11-07T10:12:00Z","updated":"2026-11-07T10:13:00Z","agent":"d"}"#,
    );
    assert_eq!(
        scan(root).stdout,
        format!(
            "\
PROBLEM 001 status file unreadable: {}: missing 'updated'
PROBLEM 001 status file unreadable: {}: bad 'updated' timestamp '2026-11-07T10:00:00'
PROBLEM 001 c reports blocked: db down
PROBLEM 001 status file unreadable: {}: missing 'started'
PROBLEM 001 status file unreadable: {}: missing 'phase'
PROBLEM 003 is 'building' but has no status file: the worker never started or died
",
            job_file("status-001-a.json"),
            job_file("status-001-b.json"),
            job_file("status-001-c.json"),
            job_file("status-001-d.json")
        )
    );
    fs::remove_dir_all(root.join(".job")).unwrap();
    job(
        root,
        ".job/status-001-a.json",
        r#"{"ticket":"001","phase":"done","updated":"2026-11-07T10:13:00Z","agent":"a"}"#,
    );
    job(
        root,
        ".job/status-001-b.json",
        &heartbeat("building", 70, 2, ""),
    );
    assert_eq!(
        scan(root).stdout,
        format!(
            "\
PROBLEM 001 status file unreadable: {}: missing 'started'
PROBLEM 001 slow: building for 70 min
PROBLEM 003 is 'building' but has no status file: the worker never started or died
",
            job_file("status-001-a.json")
        )
    );
}

// Captured from board.py at 06e3e63: a typo, an empty value, nan or inf falls back to the default;
// any finite number, even a negative one, is used as it is.
#[test]
fn a_limit_that_is_not_a_finite_number_falls_back_to_its_default() {
    let t = fixture();
    let root = t.path();
    set_building(root, "001");
    job(
        root,
        ".job/status-001-a.json",
        &heartbeat("building", 41, 40, ""),
    );
    for text in [
        "stale_min=abc\n",
        "stale_min=\n",
        "stale_min=nan\nslow_min=inf\n",
    ] {
        conf(root, text);
        assert_eq!(
            scan(root).stdout,
            "PROBLEM 001 a silent for 40 min in phase 'building'\n",
            "{text}"
        );
    }
    job(
        root,
        ".job/status-001-a.json",
        &heartbeat("building", 3, 2, ""),
    );
    conf(root, "stale_min=-1\n");
    assert_eq!(
        scan(root).stdout,
        "PROBLEM 001 a silent for 2 min in phase 'building'\n"
    );
}
