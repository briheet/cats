//! Public macOS power APIs. No SMC, private IOReport, subprocesses or privileges.
use crate::model::{Battery, Thermal};
use objc2_core_foundation::{
    CFArray, CFBoolean, CFDictionary, CFNumber, CFRetained, CFString, CFType,
};
use objc2_foundation::{NSProcessInfo, NSProcessInfoThermalState};
use objc2_io_kit::{
    IOPSCopyPowerSourcesInfo, IOPSCopyPowerSourcesList, IOPSGetPowerSourceDescription,
};

pub fn power() -> (Option<Battery>, Option<Thermal>, bool) {
    let info = NSProcessInfo::processInfo();
    let thermal = match info.thermalState() {
        NSProcessInfoThermalState::Nominal => Some(Thermal::Nominal),
        NSProcessInfoThermalState::Fair => Some(Thermal::Fair),
        NSProcessInfoThermalState::Serious => Some(Thermal::Serious),
        NSProcessInfoThermalState::Critical => Some(Thermal::Critical),
        _ => None,
    };
    (battery(), thermal, info.isLowPowerModeEnabled())
}

fn number(dict: &CFDictionary<CFString, CFType>, key: &str) -> Option<f64> {
    dict.get(&CFString::from_str(key))?
        .downcast::<CFNumber>()
        .ok()?
        .as_f64()
}
fn boolean(dict: &CFDictionary<CFString, CFType>, key: &str) -> Option<bool> {
    Some(
        dict.get(&CFString::from_str(key))?
            .downcast::<CFBoolean>()
            .ok()?
            .as_bool(),
    )
}
fn string(dict: &CFDictionary<CFString, CFType>, key: &str) -> Option<String> {
    Some(
        dict.get(&CFString::from_str(key))?
            .downcast::<CFString>()
            .ok()?
            .to_string(),
    )
}
fn battery() -> Option<Battery> {
    let info = IOPSCopyPowerSourcesInfo()?;
    // SAFETY: info is the retained opaque snapshot required by IOPS; each source
    // belongs to its list, and both remain alive while descriptions are read.
    let list = unsafe { IOPSCopyPowerSourcesList(Some(&info)) }?;
    // SAFETY: IOPS documents this array as CFTypeRef entries, not raw pointers.
    let list = unsafe { CFRetained::cast_unchecked::<CFArray<CFType>>(list) };
    for source in list.iter() {
        let Some(dict) = (unsafe { IOPSGetPowerSourceDescription(Some(&info), Some(&source)) })
        else {
            continue;
        };
        // SAFETY: IOPS descriptions have CFString keys and CFType values; values
        // are dynamically downcast below rather than assuming their types.
        let dict = unsafe { CFRetained::cast_unchecked::<CFDictionary<CFString, CFType>>(dict) };
        if string(&dict, "Type").as_deref() != Some("InternalBattery") {
            continue;
        }
        let current = number(&dict, "Current Capacity")?;
        let max = number(&dict, "Max Capacity")?;
        if !current.is_finite() || !max.is_finite() || max <= 0. || current < 0. {
            return None;
        }
        return Some(Battery {
            percent: (current / max * 100.).clamp(0., 100.),
            charging: boolean(&dict, "Is Charging"),
            plugged_in: string(&dict, "Power Source State").map(|s| s == "AC Power"),
        });
    }
    None
}
