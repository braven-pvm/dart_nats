namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    /// <summary>
    /// More specific state within a given VO2MasterDeviceState.
    /// For example, 
    /// </summary>
    public enum VO2MasterDeviceSubState
    {
        /// <summary>
        /// No state.
        /// </summary>
        None,
        /// <summary>
        /// Waiting for minimum breathing requirements to be met before calibrating.
        /// </summary>
        FlowDelay,
        /// <summary>
        /// Average gas and environmental values.
        /// </summary>
        Average
    }
}
