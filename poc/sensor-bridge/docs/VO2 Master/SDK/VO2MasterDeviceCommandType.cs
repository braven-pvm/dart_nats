namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    /// <summary>
    /// Bluetooth commands sent or received from VO2 Master Analyzer.
    /// Last updated: Nov 27, 2020
    /// </summary>
    public enum VO2MasterDeviceCommandType
    {
        /// <summary>
        /// Unrecognized response. Unused.
        /// </summary>
        UnknownResponse = 0,
        /// <summary>
        /// Set device state.
        /// </summary>
        SetState,
        /// <summary>
        /// Get device state.
        /// </summary>
        GetState,
        /// <summary>
        /// Set venturi size.
        /// </summary>
        SetVenturiSize,
        /// <summary>
        /// Get venturi size.
        /// </summary>
        GetVenturiSize,
        /// <summary>
        /// Get the 0-100% gas calibration progress.
        /// (V1.X ambient calibration only)
        /// </summary>
        GetCalibrationProgress,
        /// <summary>
        /// Device sends a new device error. Not a getter.
        /// </summary>
        Error,
        /// <summary>
        /// Set environmental correction mode.
        /// Depreciated as of V1.4.
        /// </summary>
        SetVolumeCorrectionMode,
        /// <summary>
        /// Get environmental correction mode.
        /// Depreciated as of V1.4.
        /// </summary>
        GetVolumeCorrectionMode,
        /// <summary>
        /// Get the current o2 cell age (0-100%). Never implemented.
        /// </summary>
        GetO2CellAge,
        /// <summary>
        /// Resets original o2 cell reading.
        /// This should only be used if a new o2 cell is installed
        /// and the device isn't automatically correcting for it.
        /// Never implemented.
        /// </summary>
        ResetO2CellAge,
        /// <summary>
        /// Stops the device from turning itself off after a predetermined amount of time it sits idle.
        /// </summary>
        SetIdleTimeoutMode,
        /// <summary>
        /// Allows the device to turn itself off after a predetermined amount of time it sits idle.
        /// </summary>
        GetIdleTimeoutMode,
        /// <summary>
        /// Set whether the device should switch to calibration mode periodically.
        /// </summary>
        SetAutoRecalibMode,
        /// <summary>
        /// Get whether the device should switch to calibration mode periodically.
        /// </summary>
        GetAutoRecalibMode,
        /// <summary>
        /// Sent from firmware to phone, when breath state changes.
        /// </summary>
        BreathStateChanged,
        /// <summary>
        /// Request that the device enters firmware update mode.
        /// </summary>
        RequestEnterDfuMode,
        /// <summary>
        /// Unused.
        /// </summary>
        RequestForceDiffpCalib,
        /// <summary>
        /// Unused.
        /// </summary>
        GetGasCalibFlags,
        /// <summary>
        /// Get the latest gas calibration info.
        /// </summary>
        GetGasCalibrationInfo,
        /// <summary>
        /// Set mask size.
        /// </summary>
        SetMaskSize,
        /// <summary>
        /// Get mask size.
        /// </summary>
        GetMaskSize,
        /// <summary>
        /// Set syringe flow calibration goal volume.
        /// </summary>
        SetSyringeVolume,
        /// <summary>
        /// Get syringe flow calibration goal volume.
        /// </summary>
        GetSyringeVolume,
        /// <summary>
        /// Set syringe flow calibration goal breath count.
        /// </summary>
        SetSyringeBreathCount,
        /// <summary>
        /// Get syringe flow calibration goal breath count.
        /// </summary>
        GetSyringeBreathCount,
        /// <summary>
        /// Get syringe flow clibration venturi flags.
        /// </summary>
        GetSyringeFlags,
        /// <summary>
        /// Get sub-state of device like gas calibration state.
        /// </summary>
        GetSubState,
        /// <summary>
        /// Get percent completion of syringe calibration: x/y breaths.
        /// </summary>
        GetSyringeProgress
    };
}
