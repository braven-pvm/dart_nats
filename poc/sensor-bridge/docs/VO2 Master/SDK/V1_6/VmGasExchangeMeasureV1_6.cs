using System;
using VO2MM.Common.Diagnostics;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master.V1_6
{
    public class VmGasExchangeMeasureV1_6
    {
        private static TaggedLog LOG = new TaggedLog(nameof(VmGasExchangeMeasureV1_6));

        public float FeO2 { get; private set; }
        public float VO2 { get; private set; }
        public float VO2ByWeight { get; private set; }

        public bool IsDataWithinRange { get; private set; }

        private const int decimalCount = 2;
        private const double rawValueMult = 0.01;
        private const double vo2Mult = 1.0 / 6.0;
        private const int byteGoalLength = 8;

        private void UpdateIsDataWithinRange()
        {
            IsDataWithinRange =
                FeO2 > 0 &&
                FeO2 < 21 &&
                VO2 > 0 &&
                VO2 < 10000;
        }

        public static bool TryParse(byte[] bytes, float weightKg, out VmGasExchangeMeasureV1_6 measurement)
        {
            measurement = new VmGasExchangeMeasureV1_6();

            if (bytes == null || bytes.Length != byteGoalLength)
            {
                LOG.Warning("unexpected byte length.");
                return false;
            }

            var value = BitConverter.ToUInt16(bytes, 0);
            measurement.FeO2 = (float)Math.Round(value * rawValueMult, decimalCount);
            //value = BitConverter.ToUInt16(bytes, 2);
            //measurement.FeCO2 = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 4);
            measurement.VO2 = (float)Math.Round(value * vo2Mult, decimalCount);
            //value = BitConverter.ToUInt16(bytes, 6);
            //measurement.VCO2 = value;

            if (Math.Abs(weightKg) > float.Epsilon)
                measurement.VO2ByWeight = (float)Math.Round(measurement.VO2 / weightKg, decimalCount);
            else
                measurement.VO2ByWeight = 0;

            measurement.UpdateIsDataWithinRange();
            if (measurement.IsDataWithinRange)
                return true;

            LOG.Warning($"values out of expected range.");
            return false;
        }

        public override string ToString()
        {
            return $"GasExchange inRange:{IsDataWithinRange} feo2:{FeO2} vo2:{VO2}";
        }
    }
}
