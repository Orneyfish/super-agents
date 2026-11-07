//! sa-core: the native helper behind `super-agents board`, `super-agents fingerprint` and the hook
//! scripts' JSON. It replaces scripts/board.py and scripts/hookio.py with the same output and exit
//! codes, except where board.rs, scan.rs and hookio.rs say otherwise.

mod board;
mod gitroot;

use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "\
usage: sa-core board check [root]
       sa-core board set <NNN|feature-dir> <draft|ready|building|done> [root]
       sa-core board scan [root]
       sa-core board root
       sa-core fingerprint <file>
       sa-core hookio get <a.b.c>        (reads JSON on stdin)
       sa-core hookio emit <block|message|deny|context> <text>
       sa-core hookio status-init <ticket> <dir> <phase> <now> <agent>
       sa-core hookio status-set <file> <phase> <note> <now>
       sa-core --version
[root] defaults to the main checkout, even inside a worktree.";

fn main() -> ExitCode {
    // a hook can pass any bytes; an argument that is not UTF-8 gets U+FFFD instead of a panic
    let args: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    match args.as_slice() {
        ["--version"] => {
            println!("sa-core {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        ["fingerprint", file] => match board::fingerprint(Path::new(file)) {
            Ok(hex) => {
                println!("{hex}");
                ExitCode::SUCCESS
            }
            Err(e) => fail(&format!("{file}: {e}")),
        },
        ["board", "check", rest @ ..] if rest.len() <= 1 => {
            let (report, ok) = board::check(&root(rest));
            println!("{report}");
            if ok {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        ["board", "set", target, status, rest @ ..] if rest.len() <= 1 => {
            match board::set_status(&root(rest), target, status) {
                Ok(()) => {
                    println!("ok {target} -> {status}");
                    ExitCode::SUCCESS
                }
                Err(message) => fail(&message),
            }
        }
        ["board", "root"] => {
            println!("{}", gitroot::main_checkout().display());
            ExitCode::SUCCESS
        }
        _ => fail(USAGE),
    }
}

/// The optional trailing `[root]` argument, or the main checkout.
fn root(rest: &[&str]) -> PathBuf {
    rest.first()
        .map(PathBuf::from)
        .unwrap_or_else(gitroot::main_checkout)
}

fn fail(message: &str) -> ExitCode {
    eprintln!("{message}");
    ExitCode::FAILURE
}
