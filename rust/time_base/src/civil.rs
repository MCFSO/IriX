//! 日期换算（无 chrono 依赖）
//!
//! Howard Hinnant 的 `civil_from_days` / `days_from_civil` 算法，全部为整数运算，
//! 避免 f64 时间戳在 2038/2100 附近的精度与闰年问题。

/// 把 Unix 秒拆成 UTC 日历时间：年、月、日、时、分、秒。
pub fn civil_from_unix(secs: i64) -> (i32, u32, u32, u32, u32, u32) {
    let days = secs.div_euclid(86_400);
    let sod = secs.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    (
        y,
        m,
        d,
        (sod / 3_600) as u32,
        ((sod % 3_600) / 60) as u32,
        (sod % 60) as u32,
    )
}

/// 天数（1970-01-01 起）→ (year, month, day)。
pub fn civil_from_days(days: i64) -> (i32, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097; // [0, 146096]
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe as i32 + (era * 400) as i32;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = (mp + if mp < 10 { 3 } else { -9 }) as u32; // [1, 12]
    (y + i32::from(m <= 2), m, d)
}

/// (year, month, day) → 天数（1970-01-01 起，可为负）。
pub fn days_from_civil(y: i32, m: u32, d: u32) -> i64 {
    let y = i64::from(y) - i64::from(m <= 2);
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400; // [0, 399]
    let mp = i64::from(m) + if m > 2 { -3 } else { 9 }; // [0, 11]
    let doy = (153 * mp + 2) / 5 + i64::from(d) - 1; // [0, 365]
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// UTC 星期：0=周日 … 6=周六。
pub fn weekday_from_days(days: i64) -> u32 {
    // 1970-01-01 是周四（4）。
    (days + 4).rem_euclid(7) as u32
}

pub const WEEKDAYS: [&str; 7] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
pub const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/// `YYYY-MM-DDTHH:MM:SS.mmmZ`（毫秒精度，日志/FFI 常用）。
pub fn format_iso8601_ms(unix_ms: i64) -> String {
    let secs = unix_ms.div_euclid(1_000);
    let ms = unix_ms.rem_euclid(1_000) as u32;
    let (y, mo, d, h, mi, s) = civil_from_unix(secs);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}.{ms:03}Z")
}

/// `YYYY-MM-DDTHH:MM:SS.ffffffZ`（微秒精度，给证书/审计用）。
pub fn format_iso8601_us(unix_us: i64) -> String {
    let secs = unix_us.div_euclid(1_000_000);
    let us = unix_us.rem_euclid(1_000_000) as u32;
    let (y, mo, d, h, mi, s) = civil_from_unix(secs);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}.{us:06}Z")
}

/// `YYYYMMDD-HHMMSS`（备份目录/日志文件名）。
pub fn format_compact_utc(unix_s: i64) -> String {
    let (y, mo, d, h, mi, s) = civil_from_unix(unix_s);
    format!("{y:04}{mo:02}{d:02}-{h:02}{mi:02}{s:02}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn epoch_is_thursday() {
        assert_eq!(civil_from_unix(0), (1970, 1, 1, 0, 0, 0));
        assert_eq!(weekday_from_days(0), 4);
    }

    #[test]
    fn known_http_date() {
        // RFC 7231 示例：Sun, 06 Nov 1994 08:49:37 GMT
        let secs = 784_111_777;
        let (y, mo, d, h, mi, s) = civil_from_unix(secs);
        assert_eq!((y, mo, d, h, mi, s), (1994, 11, 6, 8, 49, 37));
        assert_eq!(weekday_from_days(secs.div_euclid(86_400)), 0);
    }

    #[test]
    fn leap_days_roundtrip() {
        for &(y, m, d) in &[(2024, 2, 29), (2000, 2, 29), (2025, 3, 1), (1969, 12, 31)] {
            let days = days_from_civil(y, m, d);
            assert_eq!(civil_from_days(days), (y, m, d));
        }
        // 2100 不是闰年
        assert_eq!(days_from_civil(2100, 3, 1) - days_from_civil(2100, 2, 28), 1);
    }

    #[test]
    fn formats() {
        assert_eq!(format_iso8601_ms(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(format_iso8601_ms(1_700_000_000_123), "2023-11-14T22:13:20.123Z");
        assert_eq!(format_compact_utc(784_111_777), "19941106-084937");
    }
}
