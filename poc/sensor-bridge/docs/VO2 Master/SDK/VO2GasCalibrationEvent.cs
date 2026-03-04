namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    public class VO2GasCalibrationEvent
    {
        public VO2GasCalibrationEvent(VO2MasterDeviceGasCalibInfo details)
        {
            Details = details;
        }

        public VO2MasterDeviceGasCalibInfo Details { get; private set; }
    }
}
