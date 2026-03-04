namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    /// <summary>
    /// Versions of VO2 Master Analyzer hardware.
    /// </summary>
    public enum VO2MasterDeviceVersion
    {
        Unknown,
        BetaV2,
        V1_0,
        V1_2,
        V1_3,
        V1_4,
        V1_5,
        V1_6,
    }

    public static class VO2MasterDeviceVersionHelper
    {
        /// <summary>
        /// Parses the model number string received over BLE into a version-defining enum.
        /// </summary>
        /// <param name="modelNumber"></param>
        /// <returns></returns>
        public static VO2MasterDeviceVersion TryGetVersionFromModelNumber(this string modelNumber)
        {
            if (string.IsNullOrWhiteSpace(modelNumber))
                return VO2MasterDeviceVersion.Unknown;

            var split = modelNumber.Split(new char[] { '.' }, System.StringSplitOptions.RemoveEmptyEntries);
            if (split.Length != 3)
                return VO2MasterDeviceVersion.Unknown;

            var majorRev = split[0];
            var minorRev = split[1];
            //var buildRev = split[2]; //Currently not used.

            var _devVersion = VO2MasterDeviceVersion.Unknown;
            if (majorRev == "2")
            {
                //_devVersion = VO2MasterDeviceVersion.V2_0;
            }
            else if (majorRev == "1")
            {
                switch(minorRev)
                {
                    case ("2"): _devVersion = VO2MasterDeviceVersion.V1_2; break;
                    case ("3"): _devVersion = VO2MasterDeviceVersion.V1_3; break;
                    case ("4"): _devVersion = VO2MasterDeviceVersion.V1_4; break;
                    case ("5"): _devVersion = VO2MasterDeviceVersion.V1_5; break;
                    case ("6"): _devVersion = VO2MasterDeviceVersion.V1_6; break;
                    default: _devVersion = VO2MasterDeviceVersion.V1_0; break;
                };
            }
            else if (majorRev == "0")
            {
                switch(minorRev)
                {
                    case ("18"): _devVersion = VO2MasterDeviceVersion.V1_0; break;
                    default: _devVersion = VO2MasterDeviceVersion.BetaV2; break;
                };
            }
            return _devVersion;
        }

        /// <summary>
        /// Returns true if the device supports flow syringe calibration to increase flow sensor accuracy and repeatability.
        /// </summary>
        /// <param name="version"></param>
        /// <returns></returns>
        public static bool SupportsFlowCalibration(this VO2MasterDeviceVersion version)
        {
            return version >= VO2MasterDeviceVersion.V1_5;
        }

        public static bool SupportsAmbientGasCalibration(this VO2MasterDeviceVersion version)
        {
            return true;
        }

    }
}
