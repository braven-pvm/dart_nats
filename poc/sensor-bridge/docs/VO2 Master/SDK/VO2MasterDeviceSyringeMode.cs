namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    /// <summary>
    /// Modes in which syringe calibration may operate.
    /// </summary>
    public enum VO2MasterDeviceSyringeMode
    {
        /// <summary>
        /// Syringe calibration goals: 1 litre tidal volume, ten breaths.
        /// </summary>
        OneLitreTenBreath,
        /// <summary>
        /// Syringe calibration goals: 3 litre tidal volume, ten breaths.
        /// </summary>
        ThreeLitreTenBreath
    }
}
