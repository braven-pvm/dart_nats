using System;
using VO2MM.Common.Data;
using VO2MM.Common.Diagnostics;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master.V1_6
{
    public class VmSyringeCalibrationMeasureV1_6
    {
        private static TaggedLog LOG = new TaggedLog(nameof(VmSyringeCalibrationMeasureV1_6));

        public float GoalVolume { get; private set; }
        public float Mean { get; private set; }
        public float StdDev { get; private set; }
        public float Max { get; private set; }
        public float Min { get; private set; }
        public ushort BreathCount { get; private set; }
        public VO2VenturiSize VenturiSize { get; private set; }
        public bool IsDataWithinRange { get; private set; }

        private const int decimalCount = 3;
        private const double rawValueMult = 0.001;
        private const int byteGoalLength = 14;

        private void UpdateIsDataWithinRange()
        {
            IsDataWithinRange =
                GoalVolume >= 0 &&
                GoalVolume <= 25 &&
                Mean >= 0 &&
                Mean <= 25 &&
                StdDev >= 0 &&
                StdDev <= 25 &&
                Max >= 0 &&
                Max <= 25 &&
                Min >= 0 &&
                Min <= 25 &&
                BreathCount >= 0 &&
                BreathCount <= 25;
        }

        public static bool TryParse(byte[] bytes, out VmSyringeCalibrationMeasureV1_6 measurement)
        {
            measurement = new VmSyringeCalibrationMeasureV1_6();

            if (bytes == null || bytes.Length != byteGoalLength)
            {
                LOG.Warning("unexpected byte length.");
                return false;
            }

            var value = BitConverter.ToUInt16(bytes, 0);
            measurement.GoalVolume = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 2);
            measurement.Mean = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 4);
            measurement.StdDev = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 6);
            measurement.Max = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 8);
            measurement.Min = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 10);
            measurement.BreathCount = value;

            value = BitConverter.ToUInt16(bytes, 12);
            if (!Enum.IsDefined(typeof(VO2VenturiSize), (int)value))
            {
                LOG.Warning($"VO2VenturiSize input out of range.");
                return false;
            }
            measurement.VenturiSize = (VO2VenturiSize)value;

            measurement.UpdateIsDataWithinRange();
            if (measurement.IsDataWithinRange)
                return true;

            LOG.Warning("values out of expected range.");
            return false;
        }

        /// <summary>
        /// Converts a volume of litres into a COM transfer-ready value.
        /// </summary>
        /// <param name="volume"></param>
        /// <returns></returns>
        public static ushort PrepareSyringeVolumeForTx(float volume)
        {
            return (ushort)Math.Round(volume / rawValueMult);
        }

        public override string ToString()
        {
            return $"FlowCalibration inRange:{IsDataWithinRange} min:{Min} max:{Max} mean:{Mean} std:{StdDev} goal:{GoalVolume} count:{BreathCount} venturi:{VenturiSize}";
        }
    }
}
