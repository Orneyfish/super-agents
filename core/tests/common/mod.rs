//! Helpers shared by the integration tests: run the sa-core binary and build ticket fixtures.
#![allow(dead_code)]

use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

/// 2026-11-07T10:15:00Z: the clock every test run sees (SA_CORE_NOW).
pub const NOW: u64 = 1_794_046_500;

pub struct Run {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// Runs sa-core with `args` in `dir`, with the clock pinned to NOW.
pub fn sa(dir: &Path, args: &[&str]) -> Run {
    let out = Command::new(env!("CARGO_BIN_EXE_sa-core"))
        .args(args)
        .current_dir(dir)
        .env("SA_CORE_NOW", NOW.to_string())
        .output()
        .expect("run sa-core");
    Run {
        code: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
    }
}

pub fn s(p: &Path) -> &str {
    p.to_str().expect("utf-8 temp path")
}

pub fn read(p: &Path) -> String {
    fs::read_to_string(p).unwrap()
}

/// specs/tickets/NNN-slug/{RD.md,evals.md}, the same files tests/run.sh writes.
pub fn ticket(root: &Path, nnn: &str, slug: &str, status: &str) {
    let d = root
        .join("specs")
        .join("tickets")
        .join(format!("{nnn}-{slug}"));
    fs::create_dir_all(&d).unwrap();
    fs::write(
        d.join("RD.md"),
        format!("# {slug}\n\n**Status:** {status}\n**Risk:** low\n\n## Functional requirements\n- FR-1: a\n\nUI: no\n"),
    )
    .unwrap();
    fs::write(
        d.join("evals.md"),
        "# E\n\n## E1: a\n- covers: FR-1\n- check: c\n- pass when: p\n- fail when: f\n",
    )
    .unwrap();
}

pub fn board(root: &Path, rows: &str) {
    let d = root.join("specs").join("tickets");
    fs::create_dir_all(&d).unwrap();
    fs::write(
        d.join("BOARD.md"),
        format!("# Board\n| # | Title | Status | Mode | Runs |\n|---|---|---|---|---|\n{rows}"),
    )
    .unwrap();
}

pub const ROWS: &str = "| 001 | Found | draft | team | alongside |\n| 002 | Reset | draft | solo | waits for 001: mailer |\n| 003 | Profile | draft | solo | alongside |\n";

/// Three draft tickets and their board, as in tests/run.sh.
pub fn fixture() -> tempfile::TempDir {
    let t = tempfile::tempdir().unwrap();
    for (nnn, slug) in [("001", "found"), ("002", "reset"), ("003", "profile")] {
        ticket(t.path(), nnn, slug, "draft");
    }
    board(t.path(), ROWS);
    t
}

pub fn git(dir: &Path, args: &[&str]) {
    let out = Command::new("git")
        .args([
            "-c",
            "user.email=t@t",
            "-c",
            "user.name=t",
            "-c",
            "protocol.file.allow=always",
        ])
        .args(args)
        .current_dir(dir)
        .output()
        .expect("run git");
    assert!(
        out.status.success(),
        "git {args:?} failed in {}: {}",
        dir.display(),
        String::from_utf8_lossy(&out.stderr)
    );
}

/// Like `sa`, with `input` on stdin.
pub fn sa_stdin(dir: &Path, args: &[&str], input: &str) -> Run {
    let mut child = Command::new(env!("CARGO_BIN_EXE_sa-core"))
        .args(args)
        .current_dir(dir)
        .env("SA_CORE_NOW", NOW.to_string())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("run sa-core");
    let mut stdin = child.stdin.take().expect("stdin is piped");
    stdin.write_all(input.as_bytes()).expect("write stdin");
    drop(stdin);
    let out = child.wait_with_output().expect("wait for sa-core");
    Run {
        code: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
    }
}

/// Like `sa`, with `first_on_path` ahead of the real PATH (to put a fake `git` or `curl` in front).
pub fn sa_path(dir: &Path, args: &[&str], first_on_path: &Path) -> Run {
    let path = format!(
        "{}:{}",
        first_on_path.display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let out = Command::new(env!("CARGO_BIN_EXE_sa-core"))
        .args(args)
        .current_dir(dir)
        .env("SA_CORE_NOW", NOW.to_string())
        .env("PATH", path)
        .output()
        .expect("run sa-core");
    Run {
        code: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
    }
}

/// A directory holding a `git` that behaves like git before 2.31: it echoes `--path-format=...` back as an
/// unknown option instead of acting on it, so every line `rev-parse` prints moves down by one.
#[cfg(unix)]
pub fn old_git() -> tempfile::TempDir {
    use std::os::unix::fs::PermissionsExt;
    let real = Command::new("sh")
        .args(["-c", "command -v git"])
        .output()
        .expect("find git");
    let real = String::from_utf8_lossy(&real.stdout).trim().to_string();
    let d = tempfile::tempdir().unwrap();
    let script = format!(
        "#!/bin/bash\nargs=(); for a in \"$@\"; do case $a in --path-format=*) echo \"$a\";; *) args+=(\"$a\");; esac; done\nexec {real} \"${{args[@]}}\"\n"
    );
    fs::write(d.path().join("git"), script).unwrap();
    fs::set_permissions(d.path().join("git"), fs::Permissions::from_mode(0o755)).unwrap();
    d
}
