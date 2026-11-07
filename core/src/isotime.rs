//! Heartbeat timestamps: `YYYY-MM-DDTHH:MM:SS[.fff]` followed by `Z` or `±HH:MM`, the form
//! job-status.sh writes (`date -u +%FT%TZ`). A timestamp without a zone is rejected rather than
//! crashing the scan, which is what board.py did.

use std::time::{SystemTime, UNIX_EPOCH};

/// Seconds since the Unix epoch now. `SA_CORE_NOW=<seconds>` pins it for tests.
pub fn now_unix() -> f64 {
    if let Some(t) = std::env::var("SA_CORE_NOW")
        .ok()
        .and_then(|v| v.parse::<f64>().ok())
    {
        return t;
    }
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

/// Seconds since the Unix epoch, or None when `s` is not a timestamp with a zone.
pub fn parse_unix(s: &str) -> Option<f64> {
    let b = s.as_bytes();
    if b.len() < 20
        || b[4] != b'-'
        || b[7] != b'-'
        || !matches!(b[10], b'T' | b't' | b' ')
        || b[13] != b':'
        || b[16] != b':'
    {
        return None;
    }
    let num = |from: usize, to: usize| -> Option<i64> {
        let part = s.get(from..to)?;
        if part.bytes().all(|c| c.is_ascii_digit()) {
            part.parse().ok()
        } else {
            None
        }
    };
    let (year, month, day) = (num(0, 4)?, num(5, 7)?, num(8, 10)?);
    let (hour, minute, second) = (num(11, 13)?, num(14, 16)?, num(17, 19)?);
    if !(1..=12).contains(&month)
        || !(1..=31).contains(&day)
        || hour > 23
        || minute > 59
        || second > 60
    {
        return None;
    }
    let mut rest = s.get(19..)?;
    let mut fraction = 0.0;
    if let Some(digits_and_zone) = rest.strip_prefix('.') {
        let n = digits_and_zone
            .bytes()
            .take_while(u8::is_ascii_digit)
            .count();
        if n == 0 {
            return None;
        }
        fraction = format!("0.{}", &digits_and_zone[..n]).parse().ok()?;
        rest = &digits_and_zone[n..];
    }
    let offset = match rest {
        "Z" | "z" => 0,
        zone if zone.len() == 6 && zone.as_bytes()[3] == b':' => {
            let sign = match zone.as_bytes()[0] {
                b'+' => 1,
                b'-' => -1,
                _ => return None,
            };
            let (h, m) = (
                zone.get(1..3)?.parse::<i64>().ok()?,
                zone.get(4..6)?.parse::<i64>().ok()?,
            );
            sign * (h * 3600 + m * 60)
        }
        _ => return None,
    };
    let days = days_from_civil(year, month, day);
    Some((days * 86_400 + hour * 3600 + minute * 60 + second - offset) as f64 + fraction)
}

/// Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant's `days_from_civil`).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

#[cfg(test)]
mod tests {
    use super::parse_unix;

    #[test]
    fn utc_offsets_and_fractions() {
        assert_eq!(parse_unix("1970-01-01T00:00:00Z"), Some(0.0));
        assert_eq!(parse_unix("2026-11-07T10:15:00Z"), Some(1_794_046_500.0));
        assert_eq!(
            parse_unix("2026-11-07T11:15:00+01:00"),
            Some(1_794_046_500.0)
        );
        assert_eq!(
            parse_unix("2026-11-07T09:15:00-01:00"),
            Some(1_794_046_500.0)
        );
        assert_eq!(parse_unix("2024-02-29T00:00:00Z"), Some(1_709_164_800.0));
        assert_eq!(parse_unix("1970-01-01T00:00:00.5Z"), Some(0.5));
    }

    #[test]
    fn no_zone_or_malformed_is_rejected() {
        for s in [
            "2026-11-07T10:15:00",
            "2026-11-07",
            "yesterday",
            "2026-13-07T10:15:00Z",
            "2026-11-07T10:15:00+0100",
            "",
        ] {
            assert_eq!(parse_unix(s), None, "{s}");
        }
    }
}
