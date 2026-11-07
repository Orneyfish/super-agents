//! scripts/sa-native.sh against a download server that accepts connections and never answers.
#![cfg(unix)]

use std::fs;
use std::net::TcpListener;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// A fake plugin root (version 9.9.9) with the launcher and a checksum line for every asset name, so the
/// one for this machine is found whatever it is. There is no local build, so the launcher must download.
fn plugin_root() -> tempfile::TempDir {
    let root = tempfile::tempdir().unwrap();
    let r = root.path();
    for d in ["scripts", ".claude-plugin", "dist/checksums"] {
        fs::create_dir_all(r.join(d)).unwrap();
    }
    fs::copy(
        concat!(env!("CARGO_MANIFEST_DIR"), "/../scripts/sa-native.sh"),
        r.join("scripts/sa-native.sh"),
    )
    .unwrap();
    fs::write(
        r.join(".claude-plugin/plugin.json"),
        "{\n  \"version\": \"9.9.9\"\n}\n",
    )
    .unwrap();
    let sums: String = [
        "x86_64-unknown-linux-musl",
        "aarch64-unknown-linux-musl",
        "x86_64-apple-darwin",
        "aarch64-apple-darwin",
    ]
    .iter()
    .map(|t| format!("{}  sa-core-{t}\n", "0".repeat(64)))
    .collect();
    fs::write(r.join("dist/checksums/v9.9.9.txt"), sums).unwrap();
    root
}

/// A server that accepts every connection, keeps it open and never replies; counts the connections.
fn blackhole() -> (String, Arc<AtomicUsize>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://127.0.0.1:{}", listener.local_addr().unwrap().port());
    let accepted = Arc::new(AtomicUsize::new(0));
    let count = Arc::clone(&accepted);
    std::thread::spawn(move || {
        let mut held = Vec::new();
        for conn in listener.incoming().flatten() {
            count.fetch_add(1, Ordering::SeqCst);
            held.push(conn);
        }
    });
    (url, accepted)
}

struct Outcome {
    code: Option<i32>,
    stderr: String,
    elapsed: Duration,
}

/// Runs the launcher in its own process group; if it is still running after `limit`, the whole group is killed.
fn run(root: &Path, cache: &Path, url: &str, limit: Duration, extra: &[(&str, &str)]) -> Outcome {
    let mut cmd = Command::new(root.join("scripts/sa-native.sh"));
    cmd.arg("--version")
        .env("XDG_CACHE_HOME", cache)
        .env("SUPER_AGENTS_CORE_URL", url)
        .env("SUPER_AGENTS_CORE_TIMEOUT", "2")
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .process_group(0);
    for (k, v) in extra {
        cmd.env(k, v);
    }
    let start = Instant::now();
    let mut child = cmd.spawn().expect("run sa-native.sh");
    let pid = child.id();
    loop {
        if child.try_wait().unwrap().is_some() {
            break;
        }
        if start.elapsed() > limit {
            let _ = Command::new("sh")
                .args(["-c", &format!("kill -KILL -- -{pid}")])
                .status();
            let _ = child.wait();
            return Outcome {
                code: None,
                stderr: String::new(),
                elapsed: start.elapsed(),
            };
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    let out = child.wait_with_output().unwrap();
    Outcome {
        code: out.status.code(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
        elapsed: start.elapsed(),
    }
}

fn leftovers(cache: &Path) -> Vec<PathBuf> {
    fs::read_dir(cache.join("super-agents/9.9.9"))
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .is_some_and(|n| n.to_string_lossy().starts_with(".download."))
        })
        .collect()
}

#[test]
fn a_download_that_never_answers_gives_up_with_exit_3_and_is_not_retried_for_ten_minutes() {
    let root = plugin_root();
    let cache = tempfile::tempdir().unwrap();
    let (url, accepted) = blackhole();
    let hang = Duration::from_secs(15);

    // eval-gate runs the launcher on every Stop, so a stalled download must end quickly, with exit 3 (never 2)
    let first = run(root.path(), cache.path(), &url, hang, &[]);
    assert_eq!(
        first.code,
        Some(3),
        "still running after {:?}; stderr: {}",
        first.elapsed,
        first.stderr
    );
    assert!(
        first.stderr.contains("could not download"),
        "{}",
        first.stderr
    );
    assert!(
        leftovers(cache.path()).is_empty(),
        "{:?}",
        leftovers(cache.path())
    );
    let tries = accepted.load(Ordering::SeqCst);
    assert!(tries >= 1, "the launcher never connected");

    // the next hook does not pay for it again
    let second = run(root.path(), cache.path(), &url, hang, &[]);
    assert_eq!(second.code, Some(3), "{}", second.stderr);
    assert!(
        second.stderr.contains("failed less than 10 minutes ago"),
        "{}",
        second.stderr
    );
    assert!(
        second.elapsed < Duration::from_secs(2),
        "{:?}",
        second.elapsed
    );
    assert_eq!(accepted.load(Ordering::SeqCst), tries, "it connected again");

    // `super-agents install-core` forces a retry
    let forced = run(
        root.path(),
        cache.path(),
        &url,
        hang,
        &[("SA_NATIVE_FORCE", "1")],
    );
    assert_eq!(forced.code, Some(3), "{}", forced.stderr);
    assert!(
        accepted.load(Ordering::SeqCst) > tries,
        "SA_NATIVE_FORCE did not retry"
    );
}
