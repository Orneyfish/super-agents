mod common;
use common::*;
use std::fs;

#[test]
fn set_a_ticket_updates_rd_md_the_board_row_and_the_fingerprint() {
    let t = fixture();
    let root = t.path();
    let r = sa(root, &["board", "set", "001", "ready", s(root)]);
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (0, "ok 001 -> ready\n"),
        "{}",
        r.stderr
    );
    let d = root.join("specs/tickets/001-found");
    assert!(read(&d.join("RD.md")).contains("\n**Status:** ready\n"));
    assert!(read(&root.join("specs/tickets/BOARD.md"))
        .contains("| 001 | Found | ready | team | alongside |\n"));
    // line 1: the same value board.py wrote for this evals.md; line 2: RD.md without its Status line
    let fp = read(&d.join(".evals.sha256"));
    let rd = sa(root, &["fingerprint-rd", s(&d.join("RD.md"))]).stdout;
    assert_eq!(
        fp,
        format!(
            "5341747a4910508fc4b4c972cce369d89888b87a959d6e26954dd69ab3d103fa\n{}  RD.md\n",
            rd.trim_end()
        )
    );
    // a status change rewrites the Status line and nothing the fingerprint covers
    assert_eq!(
        sa(root, &["board", "set", "001", "building", s(root)]).code,
        0
    );
    assert_eq!(
        sa(root, &["fingerprint-rd", s(&d.join("RD.md"))]).stdout,
        rd
    );
    assert_eq!(read(&d.join(".evals.sha256")), fp);
    // any other edit does change it, and CRLF line ends do not
    let text = read(&d.join("RD.md"));
    fs::write(d.join("crlf.md"), text.replace('\n', "\r\n")).unwrap();
    assert_eq!(
        sa(root, &["fingerprint-rd", s(&d.join("crlf.md"))]).stdout,
        rd
    );
    fs::write(
        d.join("RD.md"),
        text.replace("**Risk:** low", "**Risk:** high"),
    )
    .unwrap();
    assert_ne!(
        sa(root, &["fingerprint-rd", s(&d.join("RD.md"))]).stdout,
        rd
    );
    fs::write(d.join("RD.md"), text).unwrap();
    fs::remove_file(d.join("crlf.md")).unwrap();
    assert_eq!(
        sa(root, &["board", "check", s(root)]).stdout,
        "OK: board (3 tickets)\n"
    );
}

#[test]
fn the_fingerprint_is_written_when_a_draft_is_approved_and_not_on_a_later_ready() {
    let t = fixture();
    let root = t.path();
    let d = root.join("specs/tickets/001-found");
    let set =
        |status: &str| assert_eq!(sa(root, &["board", "set", "001", status, s(root)]).code, 0);
    set("ready");
    let approved = read(&d.join(".evals.sha256"));
    fs::write(d.join("evals.md"), "# E\n\n## E1: looser\n").unwrap();
    set("ready");
    set("building");
    set("ready");
    assert_eq!(
        read(&d.join(".evals.sha256")),
        approved,
        "an edit is not approved by setting ready again"
    );
    set("draft");
    set("ready");
    assert_ne!(
        read(&d.join(".evals.sha256")),
        approved,
        "draft -> ready approves"
    );
    fs::remove_file(d.join(".evals.sha256")).unwrap();
    set("ready");
    assert!(
        d.join(".evals.sha256").exists(),
        "a ticket approved before fingerprints existed gets one"
    );
}

#[test]
fn set_a_ticket_directory_keeps_its_board_row_in_sync() {
    let t = fixture();
    let root = t.path();
    let dir = root.join("specs/tickets/002-reset");
    let r = sa(root, &["board", "set", s(&dir), "building", s(root)]);
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert!(
        read(&root.join("specs/tickets/BOARD.md")).contains("| 002 | Reset | building | solo |")
    );
    assert!(
        !dir.join(".evals.sha256").exists(),
        "only 'ready' writes the fingerprint"
    );
}

#[test]
fn set_a_feature_directory_inserts_a_status_line_and_leaves_the_board_alone() {
    let t = fixture();
    let root = t.path();
    let feat = root.join("specs/checkout");
    fs::create_dir_all(&feat).unwrap();
    fs::write(feat.join("RD.md"), "# Checkout\nbody\n").unwrap();
    let before = read(&root.join("specs/tickets/BOARD.md"));
    let r = sa(root, &["board", "set", s(&feat), "building", s(root)]);
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert_eq!(
        read(&feat.join("RD.md")),
        "# Checkout\n\n**Status:** building\nbody\n"
    );
    assert_eq!(read(&root.join("specs/tickets/BOARD.md")), before);
}

#[test]
fn a_bad_status_or_target_is_refused() {
    let t = fixture();
    let root = t.path();
    let r = sa(root, &["board", "set", "001", "wip", s(root)]);
    assert_eq!(
        (r.code, r.stderr.as_str()),
        (
            1,
            "status must be one of ('draft', 'ready', 'building', 'done')\n"
        )
    );
    let r = sa(root, &["board", "set", "009", "ready", s(root)]);
    assert_eq!(
        (r.code, r.stderr.as_str()),
        (1, "no such ticket or directory: 009\n")
    );
}

// board.py rewrote these with the platform's newline (deviation D4).
#[test]
fn crlf_files_keep_their_line_endings() {
    let t = fixture();
    let root = t.path();
    let bp = root.join("specs/tickets/BOARD.md");
    fs::write(&bp, read(&bp).replace('\n', "\r\n")).unwrap();
    let rd = root.join("specs/tickets/003-profile/RD.md");
    fs::write(&rd, read(&rd).replace('\n', "\r\n")).unwrap();
    let r = sa(root, &["board", "set", "003", "done", s(root)]);
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert!(read(&bp).contains("| 003 | Profile | done | solo | alongside |\r\n"));
    assert!(read(&rd).contains("\r\n**Status:** done\r\n"));
    assert!(
        !read(&bp).replace("\r\n", "").contains('\n'),
        "no bare LF was introduced"
    );
}

#[test]
fn concurrent_sets_do_not_lose_rows() {
    let t = fixture();
    let root = t.path().to_path_buf();
    let runs: Vec<_> = ["001", "002", "003"]
        .into_iter()
        .map(|n| {
            let root = root.clone();
            std::thread::spawn(move || sa(&root, &["board", "set", n, "building", s(&root)]))
        })
        .collect();
    for run in runs {
        assert_eq!(run.join().unwrap().code, 0);
    }
    let b = read(&root.join("specs/tickets/BOARD.md"));
    assert_eq!(b.matches("| building |").count(), 3, "{b}");
}

// C-08: the router, check-evals and the scan read RD.md without a lock, while workers flip its status.
#[cfg(unix)]
#[test]
fn a_reader_never_sees_a_half_written_rd_md() {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    let t = fixture();
    let root = t.path().to_path_buf();
    let rd = root.join("specs/tickets/001-found/RD.md");
    let stop = Arc::new(AtomicBool::new(false));
    let reader = {
        let (rd, stop) = (rd.clone(), stop.clone());
        std::thread::spawn(move || {
            let mut torn = 0;
            while !stop.load(Ordering::Relaxed) {
                match fs::read_to_string(&rd) {
                    Ok(text) if text.contains("**Status:**") && text.ends_with("UI: no\n") => {}
                    _ => torn += 1,
                }
            }
            torn
        })
    };
    for i in 0..300 {
        let status = if i % 2 == 0 { "building" } else { "ready" };
        assert_eq!(
            sa(&root, &["board", "set", "001", status, s(&root)]).code,
            0
        );
    }
    stop.store(true, Ordering::Relaxed);
    assert_eq!(
        reader.join().unwrap(),
        0,
        "reads that saw an empty or partial RD.md"
    );
}
