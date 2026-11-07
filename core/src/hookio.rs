//! The hook scripts' JSON, as scripts/hookio.py wrote it. Claude Code parses these replies, so the
//! bytes match Python's `json.dumps`: `indent=2` for replies and heartbeats, compact for `get`, every
//! character outside printable ASCII escaped as `\uXXXX`, and object keys kept in file order.
//! Error messages differ, and so may the digits of a non-integer number; a lone surrogate escape reads as U+FFFD (deviation D7).

use serde_json::{json, Map, Value};
use std::fmt::Write;
use std::fs;
use std::path::Path;

/// `get <a.b.c>`: strings raw, other values as compact JSON, and "" for null or a missing path.
pub fn get(path: &str, input: &[u8]) -> Result<String, String> {
    let doc: Value = parse(input).map_err(|e| e.to_string())?;
    let mut value = &doc;
    for key in path.split('.').filter(|k| !k.is_empty()) {
        match value.as_object().and_then(|m| m.get(key)) {
            Some(v) => value = v,
            None => return Ok(String::new()),
        }
    }
    Ok(match value {
        Value::Null => String::new(),
        Value::String(s) => s.clone(),
        other => dumps(other, false),
    })
}

/// `emit <kind> <text>`: the reply for that hook event, or None for an unknown kind.
pub fn emit(kind: &str, text: &str) -> Option<String> {
    let reply = match kind {
        "block" => json!({"decision": "block", "reason": text}),
        "message" => json!({"systemMessage": text}),
        "deny" => json!({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": text,
        }}),
        "context" => json!({"hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": text,
        }}),
        _ => return None,
    };
    Some(dumps(&reply, true))
}

/// `status-init`: a new heartbeat record, as job-status.sh writes it.
pub fn status_init(ticket: &str, dir: &str, phase: &str, now: &str, agent: &str) -> String {
    let record = json!({
        "ticket": ticket,
        "dir": dir,
        "phase": phase,
        "started": now,
        "updated": now,
        "note": "",
        "agent": agent,
    });
    dumps(&record, true)
}

/// `status-set`: `file` with its phase, note and updated time changed; other keys keep their place.
pub fn status_set(file: &Path, phase: &str, note: &str, now: &str) -> Result<String, String> {
    let at = |e: &dyn std::fmt::Display| format!("{}: {e}", file.display());
    let text = fs::read(file).map_err(|e| at(&e))?;
    let mut record: Value = parse(&text).map_err(|e| at(&e))?;
    let map: &mut Map<String, Value> = record
        .as_object_mut()
        .ok_or_else(|| at(&"not a JSON object"))?;
    for (key, value) in [("phase", phase), ("note", note), ("updated", now)] {
        map.insert(key.to_string(), Value::from(value));
    }
    Ok(dumps(&record, true))
}

/// Python's `json.dumps(value)` with `indent=2` (pretty) or `separators=(",", ":")`, ASCII only.
fn dumps(value: &Value, pretty: bool) -> String {
    let mut out = String::new();
    write_value(&mut out, value, pretty, 0);
    out
}

fn write_value(out: &mut String, value: &Value, pretty: bool, depth: usize) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => out.push_str(&n.to_string()),
        Value::String(s) => write_string(out, s),
        Value::Array(items) => {
            let items: Vec<(Option<&str>, &Value)> = items.iter().map(|v| (None, v)).collect();
            write_container(out, ('[', ']'), &items, pretty, depth);
        }
        Value::Object(map) => {
            let items: Vec<(Option<&str>, &Value)> =
                map.iter().map(|(k, v)| (Some(k.as_str()), v)).collect();
            write_container(out, ('{', '}'), &items, pretty, depth);
        }
    }
}

fn write_container(
    out: &mut String,
    (open, close): (char, char),
    items: &[(Option<&str>, &Value)],
    pretty: bool,
    depth: usize,
) {
    out.push(open);
    if items.is_empty() {
        out.push(close);
        return;
    }
    for (i, (key, value)) in items.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        if pretty {
            out.push('\n');
            out.push_str(&"  ".repeat(depth + 1));
        }
        if let Some(key) = key {
            write_string(out, key);
            out.push_str(if pretty { ": " } else { ":" });
        }
        write_value(out, value, pretty, depth + 1);
    }
    if pretty {
        out.push('\n');
        out.push_str(&"  ".repeat(depth));
    }
    out.push(close);
}

/// A JSON string the way Python's `ensure_ascii` writes it.
fn write_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            ' '..='~' => out.push(c),
            _ => {
                for unit in c.encode_utf16(&mut [0; 2]) {
                    let _ = write!(out, "\\u{unit:04x}");
                }
            }
        }
    }
    out.push('"');
}

/// Parses JSON after replacing every unpaired surrogate escape (\ud800-\udfff) with \ufffd. Python's json accepts
/// them and JS `JSON.stringify` writes one for a string cut inside an emoji, but serde_json refuses the whole
/// document, and a failed parse makes every gate see an empty value and wave the call through.
fn parse(input: &[u8]) -> Result<Value, serde_json::Error> {
    serde_json::from_slice(&replace_lone_surrogates(input))
}

fn replace_lone_surrogates(input: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(input.len());
    let mut i = 0;
    while i < input.len() {
        if input[i] != b'\\' {
            out.push(input[i]);
            i += 1;
        } else if let (Some(b'u'), Some(unit)) = (input.get(i + 1).copied(), hex4(input, i + 2)) {
            let low_follows = input.get(i + 6) == Some(&b'\\')
                && input.get(i + 7) == Some(&b'u')
                && hex4(input, i + 8).is_some_and(|lo| (0xDC00..0xE000).contains(&lo));
            if (0xD800..0xDC00).contains(&unit) && low_follows {
                out.extend_from_slice(&input[i..i + 12]); // a valid pair stays as it is
                i += 12;
            } else if (0xD800..0xE000).contains(&unit) {
                out.extend_from_slice(b"\\ufffd");
                i += 6;
            } else {
                out.extend_from_slice(&input[i..i + 6]);
                i += 6;
            }
        } else {
            // any other escape: keep the backslash and the character after it, so `\\udc00` is not read as `\udc00`
            out.push(b'\\');
            out.extend(input.get(i + 1));
            i += 2;
        }
    }
    out
}

fn hex4(b: &[u8], at: usize) -> Option<u32> {
    let digits = b.get(at..at + 4)?;
    if !digits.iter().all(u8::is_ascii_hexdigit) {
        return None;
    }
    u32::from_str_radix(std::str::from_utf8(digits).ok()?, 16).ok()
}

#[cfg(test)]
mod tests {
    use super::dumps;
    use serde_json::json;

    // Each expected string is what Python 3's json.dumps printed for the same value.
    #[test]
    fn strings_are_escaped_as_python_does_with_ensure_ascii() {
        let v = json!("q\"b\\s/\n\r\t\u{8}\u{c}\u{1}\u{7f}\u{e9}\u{1f600}");
        assert_eq!(
            dumps(&v, false),
            r#""q\"b\\s/\n\r\t\b\f\u0001\u007f\u00e9\ud83d\ude00""#
        );
    }

    #[test]
    fn lone_surrogate_escapes_become_fffd_and_nothing_else_changes() {
        use super::replace_lone_surrogates as fix;
        let f = |s: &str| String::from_utf8(fix(s.as_bytes())).unwrap();
        assert_eq!(f(r#""a\udc00b""#), r#""a\ufffdb""#);
        assert_eq!(f(r#""\ud800""#), r#""\ufffd""#);
        assert_eq!(f(r#""\ud800A""#), r#""\ufffdA""#);
        assert_eq!(f(r#""😀""#), r#""😀""#);
        assert_eq!(f(r#""\\udc00 \\""#), r#""\\udc00 \\""#);
        assert_eq!(f(r#""é\n\"""#), r#""é\n\"""#);
        assert_eq!(f(r#"\u12"#), r#"\u12"#);
    }

    #[test]
    fn containers_match_python_indent_2_and_compact_separators() {
        let v = json!({"b": [1, {"c": null}], "a": {}, "e": [], "t": true});
        assert_eq!(
            dumps(&v, true),
            "{\n  \"b\": [\n    1,\n    {\n      \"c\": null\n    }\n  ],\n  \"a\": {},\n  \"e\": [],\n  \"t\": true\n}"
        );
        assert_eq!(
            dumps(&v, false),
            r#"{"b":[1,{"c":null}],"a":{},"e":[],"t":true}"#
        );
    }
}
