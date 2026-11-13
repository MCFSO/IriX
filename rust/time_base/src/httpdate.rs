//! HTTP 日期（RFC 7231 IMF-fixdate）解析与格式化。
//!
//! 用途：
//! 1. 从 HTTPS 响应的 `Date` 头计算“服务器日期 - 本地时间”的偏差，作为时间系统的
//!    旁路诊断（绝不直接用它拨钟，避免被单个恶意服务器操纵时间）；
//! 2. FFI 向 Dart 提供标准 HTTP 日期字符串，写请求头/日志时无需再依赖系统时间。

use crate::civil::{civil_from_unix, weekday_from_days, MONTHS, WEEKDAYS};

/// 解析 HTTP 日期。支持 RFC 7231 的三种历史格式：
/// - `Sun, 06 Nov 1994 08:49:37 GMT`（IMF-fixdate，优先）
/// - `Sunday, 06-Nov-94 08:49:37 GMT`（RFC 850）
/// - `Sun Nov  6 08:49:37 1994`（asctime）
pub fn parse_http_date(s: &str) -> Option<i64> {
    let s = s.trim();
    if s.is_empty() {
        return None;
    }
    parse_imf_fixdate(s)
        .or_else(|| parse_rfc850(s))
        .or_else(|| parse_asctime(s))
}

fn month_index(name: &str) -> Option<u32> {
    MONTHS
        .iter()
        .position(|m| m.eq_ignore_ascii_case(name))
        .map(|i| i as u32 + 1)
}

fn parse_hms(s: &str) -> Option<(u32, u32, u32)> {
    let mut it = s.split(':');
    let h: u32 = it.next()?.parse().ok()?;
    let m: u32 = it.next()?.parse().ok()?;
    let sec: u32 = it.next()?.parse().ok()?;
    if it.next().is_some() || h > 23 || m > 59 || sec > 60 {
        return None;
    }
    Some((h, m, sec))
}

fn days_to_unix(y: i32, mo: u32, d: u32, h: u32, mi: u32, s: u32) -> Option<i64> {
    if !(1..=12).contains(&mo) || !(1..=31).contains(&d) || h > 23 || mi > 59 || s > 60 {
        return None;
    }
    let days = crate::civil::days_from_civil(y, mo, d);
    // 校验日期真实存在（例如 2 月 30 日会被规范化为 3 月 2 日）
    if crate::civil::civil_from_days(days) != (y, mo, d) {
        return None;
    }
    Some(days * 86_400 + i64::from(h) * 3_600 + i64::from(mi) * 60 + i64::from(s))
}

fn parse_imf_fixdate(s: &str) -> Option<i64> {
    // Sun, 06 Nov 1994 08:49:37 GMT
    let mut parts = s.split_whitespace();
    let _weekday = parts.next()?;
    let day: u32 = parts.next()?.parse().ok()?;
    let month = month_index(parts.next()?)?;
    let year: i32 = parts.next()?.parse().ok()?;
    let (h, mi, sec) = parse_hms(parts.next()?)?;
    if !parts.next()?.eq_ignore_ascii_case("GMT") || parts.next().is_some() {
        return None;
    }
    days_to_unix(year, month, day, h, mi, sec)
}

fn parse_rfc850(s: &str) -> Option<i64> {
    // Sunday, 06-Nov-94 08:49:37 GMT
    let mut parts = s.split_whitespace();
    let _weekday = parts.next()?;
    let date = parts.next()?;
    let mut dit = date.split('-');
    let day: u32 = dit.next()?.parse().ok()?;
    let month = month_index(dit.next()?)?;
    let mut year: i32 = dit.next()?.parse().ok()?;
    if dit.next().is_some() {
        return None;
    }
    if year < 70 {
        year += 2000;
    } else if year < 100 {
        year += 1900;
    }
    let (h, mi, sec) = parse_hms(parts.next()?)?;
    if !parts.next()?.eq_ignore_ascii_case("GMT") {
        return None;
    }
    days_to_unix(year, month, day, h, mi, sec)
}

fn parse_asctime(s: &str) -> Option<i64> {
    // Sun Nov  6 08:49:37 1994
    let mut parts = s.split_whitespace();
    let _weekday = parts.next()?;
    let month = month_index(parts.next()?)?;
    let day: u32 = parts.next()?.parse().ok()?;
    let (h, mi, sec) = parse_hms(parts.next()?)?;
    let year: i32 = parts.next()?.parse().ok()?;
    days_to_unix(year, month, day, h, mi, sec)
}

/// 格式化为 `Sun, 06 Nov 1994 08:49:37 GMT`。
pub fn format_http_date(unix_s: i64) -> String {
    let days = unix_s.div_euclid(86_400);
    let sod = unix_s.rem_euclid(86_400);
    let (y, mo, d, _, _, _) = civil_from_unix(unix_s);
    let weekday = WEEKDAYS[weekday_from_days(days) as usize];
    let month = MONTHS[(mo - 1) as usize];
    let (h, mi, s) = (sod / 3600, (sod % 3600) / 60, sod % 60);
    format!(
        "{weekday}, {d:02} {month} {y:04} {h:02}:{mi:02}:{s:02} GMT"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_imf_fixdate() {
        assert_eq!(
            parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT"),
            Some(784_111_777)
        );
        assert_eq!(
            format_http_date(784_111_777),
            "Sun, 06 Nov 1994 08:49:37 GMT"
        );
    }

    #[test]
    fn parses_legacy_formats() {
        assert_eq!(
            parse_http_date("Sunday, 06-Nov-94 08:49:37 GMT"),
            Some(784_111_777)
        );
        assert_eq!(
            parse_http_date("Sun Nov  6 08:49:37 1994"),
            Some(784_111_777)
        );
    }

    #[test]
    fn rejects_garbage() {
        assert_eq!(parse_http_date(""), None);
        assert_eq!(parse_http_date("not a date"), None);
        assert_eq!(parse_http_date("Sun, 31 Feb 2024 00:00:00 GMT"), None);
    }

    #[test]
    fn roundtrips_every_day() {
        let mut t = 0;
        while t < 4_102_444_800 {
            // 1970..2100，每 13 天抽一个点
            let s = format_http_date(t);
            assert_eq!(parse_http_date(&s), Some(t), "{s}");
            t += 13 * 86_400;
        }
    }
}
