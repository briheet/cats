//! Signal handlers only set an atomic flag; cleanup happens in ordinary code.
use std::{
    io,
    sync::atomic::{AtomicBool, Ordering},
};

static STOP: AtomicBool = AtomicBool::new(false);

extern "C" fn request_stop(_: libc::c_int) {
    STOP.store(true, Ordering::Relaxed);
}

pub fn requested() -> bool {
    STOP.load(Ordering::Relaxed)
}

pub fn install() -> io::Result<()> {
    for signal in [libc::SIGINT, libc::SIGTERM] {
        // SAFETY: the handler has C ABI and performs only a lock-free atomic store.
        if unsafe { libc::signal(signal, request_stop as *const () as usize) } == libc::SIG_ERR {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}
