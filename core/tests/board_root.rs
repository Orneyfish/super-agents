mod common;
use common::*;
use std::fs;
use std::path::{Path, PathBuf};

/// `board root` run in `dir`, resolved, so `C:/x`, `C:\x` and a symlinked temp folder compare equal.
fn root_from(dir: &Path) -> PathBuf {
    let r = sa(dir, &["board", "root"]);
    assert_eq!(r.code, 0, "{}", r.stderr);
    fs::canonicalize(r.stdout.trim_end()).unwrap()
}

fn real(p: &Path) -> PathBuf {
    fs::canonicalize(p).unwrap()
}

/// `<t>/sup` with `<t>/sub`, a repository with one ticket, added as its submodule; returns `sup/sub`.
fn submodule(t: &Path) -> PathBuf {
    let sub = t.join("sub");
    fs::create_dir_all(&sub).unwrap();
    ticket(&sub, "001", "found", "draft");
    board(&sub, "| 001 | Found | draft | solo | alongside |\n");
    git(&sub, &["init", "-q", "-b", "main"]);
    git(&sub, &["add", "."]);
    git(&sub, &["commit", "-qm", "tickets"]);
    let sup = t.join("sup");
    fs::create_dir_all(&sup).unwrap();
    git(&sup, &["init", "-q", "-b", "main"]);
    git(&sup, &["submodule", "add", "-q", "../sub", "sub"]);
    sup.join("sub")
}

#[test]
fn root_defaults_to_the_main_checkout_from_a_subdirectory_and_a_worktree() {
    let t = fixture();
    let repo = t.path();
    git(repo, &["init", "-q", "-b", "main"]);
    git(repo, &["add", "."]);
    git(repo, &["commit", "-qm", "tickets"]);
    fs::create_dir_all(repo.join("sub/deep")).unwrap();
    let r = sa(&repo.join("sub/deep"), &["board", "check"]);
    assert_eq!(r.stdout, "OK: board (3 tickets)\n", "{}", r.stderr);
    assert_eq!(root_from(&repo.join("sub/deep")), real(repo));
    git(repo, &["worktree", "add", "-q", "wt", "-b", "w"]);
    fs::remove_file(repo.join("wt/specs/tickets/BOARD.md")).unwrap(); // only the main checkout's board counts
    let r = sa(&repo.join("wt"), &["board", "check"]);
    assert_eq!(r.stdout, "OK: board (3 tickets)\n", "{}", r.stderr);
    assert_eq!(root_from(&repo.join("wt")), real(repo));
}

#[test]
fn root_inside_a_submodule_is_the_submodule_checkout() {
    let t = tempfile::tempdir().unwrap();
    let checkout = submodule(t.path());
    let r = sa(&checkout, &["board", "check"]);
    assert_eq!(r.stdout, "OK: board (1 tickets)\n", "{}", r.stderr);
    assert_eq!(root_from(&checkout), real(&checkout));
}

// The plan for e93ef43 answered <sup>/.git/modules/sub here: the first entry of `git worktree list`.
#[test]
fn root_inside_a_worktree_of_a_submodule_is_the_submodule_checkout() {
    let t = tempfile::tempdir().unwrap();
    let checkout = submodule(t.path());
    git(
        &checkout,
        &["worktree", "add", "-q", "../../subwt", "-b", "w"],
    );
    let wt = t.path().join("subwt");
    fs::remove_file(wt.join("specs/tickets/BOARD.md")).unwrap(); // only the main checkout's board counts
    let r = sa(&wt, &["board", "check"]);
    assert_eq!(r.stdout, "OK: board (1 tickets)\n", "{}", r.stderr);
    assert_eq!(root_from(&wt), real(&checkout));
}

// board.py answers the folder around the git dir here: `t` instead of `t/checkout` (deviation D3).
#[test]
fn root_of_a_separate_git_dir_repository_is_its_checkout() {
    let t = tempfile::tempdir().unwrap();
    let gitdir = format!("--separate-git-dir={}", s(&t.path().join("gitdir")));
    git(t.path(), &["init", "-q", &gitdir, "checkout"]);
    let checkout = t.path().join("checkout");
    fs::create_dir_all(checkout.join("deep")).unwrap();
    assert_eq!(root_from(&checkout.join("deep")), real(&checkout));
}
