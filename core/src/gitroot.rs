//! The main checkout: where BOARD.md and the approved ticket files live, even when a command runs
//! inside a worker's worktree. Outside a linked worktree it is the checkout we are in
//! (`--show-toplevel`), which is right for submodules and `git init --separate-git-dir` repositories
//! too. Inside a linked worktree it is what board.py answers: the `core.worktree` of the common git
//! dir when set (a submodule's git dir lives in `<superproject>/.git/modules/<name>` and records its
//! checkout there), otherwise the parent of the common git dir. board.py uses that rule everywhere,
//! which names the folder around the git dir of a `--separate-git-dir` repository (deviation D3).

use std::path::{Component, Path, PathBuf};
use std::process::Command;

/// The main checkout of the repository around the current directory, or the current directory outside git.
pub fn main_checkout() -> PathBuf {
    let here = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let Some(out) = git(&[
        "rev-parse",
        "--path-format=absolute",
        "--git-dir",
        "--git-common-dir",
        "--show-toplevel",
    ]) else {
        return here;
    };
    let mut lines = out.lines();
    let (Some(git_dir), Some(common_dir), Some(top)) = (lines.next(), lines.next(), lines.next())
    else {
        return here;
    };
    if git_dir == common_dir {
        return PathBuf::from(top);
    }
    // a linked worktree: ask the repository it belongs to
    let common = Path::new(common_dir);
    match git(&[
        &format!("--git-dir={common_dir}"),
        "config",
        "--get",
        "core.worktree",
    ]) {
        Some(worktree) => normalize(&common.join(worktree.trim())),
        None => common
            .parent()
            .map_or_else(|| PathBuf::from(top), Path::to_path_buf),
    }
}

/// `a/b/../c` as `a/c`, without touching the filesystem: git's paths are already absolute.
fn normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other),
        }
    }
    out
}

/// stdout of a successful git command.
fn git(args: &[&str]) -> Option<String> {
    let out = Command::new("git").args(args).output().ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}
