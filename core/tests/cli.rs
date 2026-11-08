mod common;
use common::*;
use std::fs;

#[test]
fn version_prints_the_crate_version() {
    let t = tempfile::tempdir().unwrap();
    let r = sa(t.path(), &["--version"]);
    assert_eq!(r.code, 0);
    assert_eq!(r.stdout, format!("sa-core {}\n", env!("CARGO_PKG_VERSION")));
}

#[test]
fn unknown_arguments_print_usage_and_exit_1() {
    let t = tempfile::tempdir().unwrap();
    for args in [
        &[][..],
        &["board"][..],
        &["board", "set", "001"][..],
        &["nope"][..],
    ] {
        let r = sa(t.path(), args);
        assert_eq!(r.code, 1, "{args:?}");
        assert!(
            r.stderr.starts_with("usage: sa-core"),
            "{args:?}: {}",
            r.stderr
        );
    }
}

#[test]
fn fingerprint_is_lowercase_sha256_hex() {
    let t = tempfile::tempdir().unwrap();
    fs::write(t.path().join("abc"), "abc").unwrap();
    let r = sa(t.path(), &["fingerprint", "abc"]);
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert_eq!(
        r.stdout,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n"
    );
}

#[test]
fn fingerprint_of_a_missing_file_fails() {
    let t = tempfile::tempdir().unwrap();
    let r = sa(t.path(), &["fingerprint", "nope"]);
    assert_eq!(r.code, 1);
    assert!(r.stderr.starts_with("nope: "), "{}", r.stderr);
}

// Git's autocrlf checks a worker's worktree out with CRLF; the fingerprint is of what the user approved, not of how Git wrote it.
#[test]
fn fingerprint_reads_crlf_as_lf() {
    let t = tempfile::tempdir().unwrap();
    fs::write(t.path().join("lf"), "# E\n\n## E1: a\n").unwrap();
    fs::write(t.path().join("crlf"), "# E\r\n\r\n## E1: a\r\n").unwrap();
    fs::write(t.path().join("mixed"), "# E\r\n\n## E1: a\n").unwrap();
    let lf = sa(t.path(), &["fingerprint", "lf"]).stdout;
    assert_eq!(sa(t.path(), &["fingerprint", "crlf"]).stdout, lf);
    assert_eq!(sa(t.path(), &["fingerprint", "mixed"]).stdout, lf);
    // a carriage return that is not part of CRLF is content, and still counts
    fs::write(t.path().join("lone"), "# E\r\n\n## E1: a\r").unwrap();
    assert_ne!(sa(t.path(), &["fingerprint", "lone"]).stdout, lf);
}
