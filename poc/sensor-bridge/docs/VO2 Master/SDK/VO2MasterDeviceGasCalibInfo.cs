namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    public class VO2MasterDeviceGasCalibInfo
    {
        /// <summary>
        /// Calibration progress percent complete.
        /// </summary>
        public int CalibrationProgress;
        /// <summary>
        /// True if calibration is complete.
        /// </summary>
        public bool IsCalibrated;

        /// <summary>
        /// Get a string with CalibrationProgress.
        /// </summary>
        /// <returns></returns>
        public string GetGasCalibrationProgressString()
        {
            return $"O2 Calibrating: {CalibrationProgress}%";
        }
    }   
}
