//! 进度上报 + 取消检查。
//!
//! 进度回调由 Dart 侧在主 isolate 用 `NativeCallable.listener` 创建，
//! rayon 工作线程可并发调用（内部已是原子量，无需加锁）。
//! 取消由 Dart 调用 `cancel_backup()` 置位全局标志，长任务轮询该标志。

use std::io;
use std::sync::atomic::{AtomicU64, Ordering};

/// FFI 进度回调：(已处理字节, 总字节)。
pub(crate) type ProgressCallback = extern "C" fn(u64, u64);

/// 进度上报器。`total == 0` 表示无法预估（UI 显示不确定进度）。
pub(crate) struct Progress {
    cb: Option<ProgressCallback>,
    total: AtomicU64,
    done: AtomicU64,
    /// 上次上报的千分比，用于节流（避免逐文件刷屏）。
    last_permille: AtomicU64,
}

impl Progress {
    pub(crate) fn new(cb: Option<ProgressCallback>, total: u64) -> Self {
        Self {
            cb,
            total: AtomicU64::new(total),
            done: AtomicU64::new(0),
            last_permille: AtomicU64::new(u64::MAX),
        }
    }

    /// 无回调的空实现（单元测试用）。
    #[cfg(test)]
    pub(crate) fn none() -> Self {
        Self::new(None, 0)
    }

    /// 修正总量（扫描后才知道真实字节数）。
    pub(crate) fn set_total(&self, total: u64) {
        self.total.store(total, Ordering::Relaxed);
        self.emit();
    }

    /// 累加已处理字节数。
    pub(crate) fn add(&self, bytes: u64) {
        self.done.fetch_add(bytes, Ordering::Relaxed);
        self.emit();
    }

    /// 直接按百分比上报（rsync 只知道百分比，不知道已复制字节数）。
    pub(crate) fn report_permille(&self, permille: u64) {
        let permille = permille.min(1000);
        if self
            .last_permille
            .swap(permille, Ordering::Relaxed)
            .eq(&permille)
        {
            return;
        }
        if let Some(cb) = self.cb {
            cb(permille, 1000);
        }
    }

    /// 结束前补报一次 100%，让 UI 进度条走满。
    pub(crate) fn finish(&self) {
        let total = self.total.load(Ordering::Relaxed);
        if let Some(cb) = self.cb {
            cb(if total == 0 { 0 } else { total }, total);
        }
        self.last_permille.store(1000, Ordering::Relaxed);
    }

    fn emit(&self) {
        let total = self.total.load(Ordering::Relaxed);
        if total == 0 {
            return;
        }
        let done = self.done.load(Ordering::Relaxed);
        let permille = done.saturating_mul(1000) / total;
        if self
            .last_permille
            .swap(permille, Ordering::Relaxed)
            .eq(&permille)
        {
            return;
        }
        if let Some(cb) = self.cb {
            cb(done.min(total), total);
        }
    }
}

/// 用户是否点了「取消」。
pub(crate) fn is_cancelled() -> bool {
    crate::cancel_requested()
}

/// 取消错误：调用方统一映射为「已取消」返回码，不做 panic。
pub(crate) fn cancelled_error() -> io::Error {
    io::Error::new(io::ErrorKind::Interrupted, "用户取消")
}

/// 任务开始/每个文件前调用，取消时提前返回错误。
pub(crate) fn check_cancel() -> io::Result<()> {
    if is_cancelled() {
        Err(cancelled_error())
    } else {
        Ok(())
    }
}

/// 判断是否是取消错误。
pub(crate) fn is_cancel_error(err: &io::Error) -> bool {
    err.kind() == io::ErrorKind::Interrupted
}
