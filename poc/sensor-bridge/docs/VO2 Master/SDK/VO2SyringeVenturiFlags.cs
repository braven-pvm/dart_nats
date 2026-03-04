using System;
using VO2MM.Common.Data;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    /// <summary>
    /// Single byte containing syringe calibration status of all user piece sizes.
    /// </summary>
    [Flags]
    public enum VO2SyringeVenturiFlags
    {
        RestingIsCalibrated = 1,
        MediumIsCalibrated = 2,
        LargeIsCalibrated = 4,
    }

    public static class VO2SyringeVenturiFlagsHelper
    {
        /// <summary>
        /// Gets the flags enum value corresponding to the given user piece size.
        /// </summary>
        /// <param name="size"></param>
        /// <returns></returns>
        public static VO2SyringeVenturiFlags GetSyringeFlag(this VO2VenturiSize size)
        {
            switch (size)
            {
                default:
                case VO2VenturiSize.Medium:
                    return VO2SyringeVenturiFlags.MediumIsCalibrated;
                case VO2VenturiSize.Large:
                    return VO2SyringeVenturiFlags.LargeIsCalibrated;
                case VO2VenturiSize.Resting:
                    return VO2SyringeVenturiFlags.RestingIsCalibrated;
            }
        }
    }
}
