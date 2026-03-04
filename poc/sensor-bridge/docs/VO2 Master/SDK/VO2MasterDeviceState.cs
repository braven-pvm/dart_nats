using System;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    /// <summary>
    /// Primary states of the VO2 Master Analyzer
    /// </summary>
    public enum VO2MasterDeviceState : byte
    {
        /// <summary>
        /// Device is idle, awaiting further command.
        /// </summary>
        Idle = 0,
        /// <summary>
        /// Legacy calibration of oxygen sensor to ambient
        /// (V1.4 and prior)
        /// </summary>
        CalibratingGas = 1,
        /// <summary>
        /// Polls sensors, measures breathing, and produces metrics. Device must be calibrated before recording. 
        /// </summary>
        Recording = 2,
        /// <summary>
        /// Unused.
        /// </summary>
        Unused = 3,
        /// <summary>
        /// Calibrate flow sensor using an air syringe, typicall a 3L syringe.
        /// </summary>
        CalibrateFlowSensor = 4,
        /// <summary>
        /// Zeroing flow sensor
        /// </summary>
        ZeroFlowSensor = 5
    }

    public static class VO2MasterDeviceStateHelper
    {
        public static string GetDisplayString(this VO2MasterDeviceState state)
        {
            switch (state)
            {
                case VO2MasterDeviceState.Recording:
                    return "Ready";
                case VO2MasterDeviceState.CalibrateFlowSensor:
                    return "Flow Calibration";
                case VO2MasterDeviceState.CalibratingGas:
                    return "O2 Calibration";
                case VO2MasterDeviceState.ZeroFlowSensor:
                    return "Zeroing Flow Sensor";
                default:
                    return Enum.GetName(typeof(VO2MasterDeviceState), state);
            }
        }
    }
}
