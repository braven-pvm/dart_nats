namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    public class VO2FlowCalibrationEvent
    {
        public VO2FlowCalibrationEvent(bool isCalibrated, float progress)
        {
            IsCalibrated = isCalibrated;
            Progress = progress;
        }

        public bool IsCalibrated;
        public float Progress;
    }
}
