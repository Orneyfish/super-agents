mod common;
use common::*;
use std::fs;
use std::path::Path;

fn check(root: &Path) -> Run {
    sa(root, &["board", "check", s(root)])
}

#[test]
fn a_consistent_board_is_ok() {
    let t = fixture();
    let r = check(t.path());
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (0, "OK: board (3 tickets)\n"),
        "{}",
        r.stderr
    );
}

#[test]
fn no_board_is_reported() {
    let t = tempfile::tempdir().unwrap();
    let r = check(t.path());
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (1, "FAIL: no specs/tickets/BOARD.md\n")
    );
}

#[test]
fn a_missing_dependency_is_reported() {
    let t = fixture();
    board(t.path(), &ROWS.replace("waits for 001", "waits for 009"));
    let r = check(t.path());
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (1, "FAIL: 002: waits for 009, which is not on the board\n")
    );
}

#[test]
fn a_dependency_cycle_is_reported() {
    let t = fixture();
    board(
        t.path(),
        &ROWS.replace("team | alongside", "team | waits for 002: x"),
    );
    let r = check(t.path());
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (1, "FAIL: dependency cycle 001 -> 002 -> 001\n")
    );
}

#[test]
fn a_bad_status_word_is_reported() {
    let t = fixture();
    board(
        t.path(),
        &ROWS.replace("| 003 | Profile | draft", "| 003 | Profile | wip"),
    );
    let r = check(t.path());
    assert_eq!(r.code, 1);
    assert!(
        r.stdout.contains(
            "FAIL: 003: status 'wip' is not one of ('draft', 'ready', 'building', 'done')\n"
        ),
        "{}",
        r.stdout
    );
}

// Captured from board.py at 06e3e63 with the same fixture.
#[test]
fn every_kind_of_row_problem_is_reported_in_board_py_order() {
    let t = fixture();
    fs::create_dir_all(t.path().join("specs/tickets/004-extra")).unwrap();
    board(
        t.path(),
        "| 001 | Found | ready | team | alongside |\n| 001 | Again | draft | duo | later |\n| 003 | Profile | draft | solo | alongside |\n| 005 | Gone | draft | solo | alongside |\n",
    );
    let r = check(t.path());
    assert_eq!(r.code, 1);
    assert_eq!(
        r.stdout,
        "\
FAIL: duplicate id 001
FAIL: 001: RD.md Status is 'draft', board says 'ready'
FAIL: 001: mode must be solo or team
FAIL: 001: Runs must be 'alongside' or 'waits for NNN: why'
FAIL: 005: no folder specs/tickets/005-*
FAIL: 002-reset has no board row
FAIL: 004-extra has no board row
"
    );
}
