//! sa-core: the native helper behind `super-agents board`, `super-agents fingerprint` and the hook
//! scripts' JSON. It replaces scripts/board.py and scripts/hookio.py with the same output and exit
//! codes, except where board.rs, scan.rs and hookio.rs say otherwise.

mod board;

use std::path::Path;
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
        _ => fail(USAGE),
    }
}

fn fail(message: &str) -> ExitCode {
    eprintln!("{message}");
    ExitCode::FAILURE
}
