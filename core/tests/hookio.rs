mod common;
use common::*;
use std::fs;

// Every expected value below is what scripts/hookio.py at 06e3e63 printed for the same input.

fn get(json: &str, path: &str) -> Run {
    let t = tempfile::tempdir().unwrap();
    sa_stdin(t.path(), &["hookio", "get", path], json)
}

fn emit(kind: &str, text: &str) -> Run {
    let t = tempfile::tempdir().unwrap();
    sa(t.path(), &["hookio", "emit", kind, text])
}

const DOC: &str = r#"{"a":{"b":"x y"},"n":5,"o":{"k":[1]},"z":null,"t":true,"u":{"b":1,"a":"é"}}"#;

#[test]
fn get_prints_strings_raw_and_other_values_as_compact_json() {
    for (path, want) in [
        ("a.b", "x y\n"),
        ("n", "5\n"),
        ("o", "{\"k\":[1]}\n"),
        ("t", "true\n"),
        ("u", "{\"b\":1,\"a\":\"\\u00e9\"}\n"),
        ("u.a", "é\n"),
        ("a.nope.deeper", "\n"),
        ("o.k.0", "\n"),
        ("z", "\n"),
    ] {
        let r = get(DOC, path);
        assert_eq!(
            (r.code, r.stdout.as_str()),
            (0, want),
            "{path}: {}",
            r.stderr
        );
    }
}

#[test]
fn get_of_bad_json_prints_nothing_and_exits_1() {
    let r = get("{oops", "a");
    assert_eq!((r.code, r.stdout.as_str()), (1, ""));
    assert!(r.stderr.starts_with("hookio: "), "{}", r.stderr);
}

#[test]
fn emit_prints_each_reply_byte_for_byte() {
    let r = emit("block", "line1\nline2 \"quoted\" é");
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (
            0,
            "{\n  \"decision\": \"block\",\n  \"reason\": \"line1\\nline2 \\\"quoted\\\" \\u00e9\"\n}\n"
        )
    );
    assert_eq!(
        emit("message", "hi").stdout,
        "{\n  \"systemMessage\": \"hi\"\n}\n"
    );
    assert_eq!(
        emit("deny", "why").stdout,
        "{\n  \"hookSpecificOutput\": {\n    \"hookEventName\": \"PreToolUse\",\n    \"permissionDecision\": \"deny\",\n    \"permissionDecisionReason\": \"why\"\n  }\n}\n"
    );
    assert_eq!(
        emit("context", "hi").stdout,
        "{\n  \"hookSpecificOutput\": {\n    \"hookEventName\": \"SessionStart\",\n    \"additionalContext\": \"hi\"\n  }\n}\n"
    );
}

#[test]
fn bad_hookio_arguments_print_usage_and_exit_1() {
    let t = tempfile::tempdir().unwrap();
    for args in [
        &["hookio"][..],
        &["hookio", "emit", "shout", "x"][..],
        &["hookio", "get"][..],
    ] {
        let r = sa(t.path(), args);
        assert_eq!(r.code, 1, "{args:?}");
        assert!(r.stderr.starts_with("usage: sa-core"), "{}", r.stderr);
    }
}

#[test]
fn status_init_and_status_set_write_the_heartbeat_record() {
    let t = tempfile::tempdir().unwrap();
    let r = sa(
        t.path(),
        &[
            "hookio",
            "status-init",
            "001",
            "/d",
            "building",
            "2026-11-07T10:15:00Z",
            "a",
        ],
    );
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (
            0,
            "{\n  \"ticket\": \"001\",\n  \"dir\": \"/d\",\n  \"phase\": \"building\",\n  \"started\": \"2026-11-07T10:15:00Z\",\n  \"updated\": \"2026-11-07T10:15:00Z\",\n  \"note\": \"\",\n  \"agent\": \"a\"\n}\n"
        )
    );
    // keys keep their place; new ones go last, in the order phase, note, updated
    fs::write(
        t.path().join("s.json"),
        r#"{"z": 1, "phase": "x", "ticket": "001"}"#,
    )
    .unwrap();
    let r = sa(
        t.path(),
        &[
            "hookio",
            "status-set",
            "s.json",
            "testing",
            "n é",
            "2026-11-07T10:16:00Z",
        ],
    );
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (
            0,
            "{\n  \"z\": 1,\n  \"phase\": \"testing\",\n  \"ticket\": \"001\",\n  \"note\": \"n \\u00e9\",\n  \"updated\": \"2026-11-07T10:16:00Z\"\n}\n"
        )
    );
    let r = sa(
        t.path(),
        &["hookio", "status-set", "nope.json", "testing", "", "now"],
    );
    assert_eq!((r.code, r.stdout.as_str()), (1, ""));
    assert!(r.stderr.starts_with("hookio: nope.json: "), "{}", r.stderr);
}

// Python's json accepts a lone surrogate escape; JS JSON.stringify writes one for a string cut inside an emoji.
// serde_json refused it, so `get` failed, the gates saw an empty value and let the call through.
#[test]
fn a_lone_surrogate_escape_does_not_make_get_fail() {
    let doc = r#"{"cwd":"/p","agent_type":"super-agents:first-time-user","tool_input":{"command":"cat src\udc00 x","bad":"\ud800"}}"#;
    let r = get(doc, "agent_type");
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (0, "super-agents:first-time-user\n"),
        "{}",
        r.stderr
    );
    let r = get(doc, "tool_input");
    assert_eq!(r.code, 0, "{}", r.stderr);
    assert!(r.stdout.contains("cat src"), "{}", r.stdout);
    // a valid pair, and an escaped backslash that only looks like an escape, are left exactly as they were
    let r = get(r#"{"a":"\ud83d\ude00 \\udc00"}"#, "a");
    assert_eq!(
        (r.code, r.stdout.as_str()),
        (0, "\u{1f600} \\udc00\n"),
        "{}",
        r.stderr
    );
}
