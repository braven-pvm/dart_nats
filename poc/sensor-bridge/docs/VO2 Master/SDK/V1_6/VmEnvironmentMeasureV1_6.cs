using System;
using VO2MM.Common.Diagnostics;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master.V1_6
{
    public class VmEnvironmentMeasureV1_6
    {
        private static TaggedLog LOG = new TaggedLog(nameof(VmEnvironmentMeasureV1_6));

        public float Pressure { get; private set; }
        public float Temperature { get; private set; }
        public float Humidity { get; private set; }

        public bool IsDataWithinRange { get; private set; }

        private const int decimalCount = 2;
        private const double rawValueSmallMult = 0.1;
        private const double rawValueMult = 0.01;
        private const int byteGoalLength = 10;

        private void UpdateIsDataWithinRange()
        {
            IsDataWithinRange =
                Pressure > 0 &&
                Pressure < 1200 &&
                Temperature > -25 &&
                Temperature < 85 &&
                Humidity >= 0 &&
                Humidity <= 100;
        }

        public static bool TryParse(byte[] bytes, out VmEnvironmentMeasureV1_6 measurement)
        {
            measurement = new VmEnvironmentMeasureV1_6();

            if (bytes == null || bytes.Length != byteGoalLength)
            {
                LOG.Warning("unexpected byte length.");
                return false;
            }

            var value = BitConverter.ToUInt16(bytes, 0);
            measurement.Pressure = (float)Math.Round(value * rawValueSmallMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 2);
            measurement.Temperature = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 4);
            measurement.Humidity = (float)Math.Round(value * rawValueMult, decimalCount);
            //value = BitConverter.ToUInt16(bytes, 6);
            //measurement.AmbientO2 = (float)Math.Round(value * rawValueMult, decimalCount);
            //value = BitConverter.ToUInt16(bytes, 8);
            //measurement.AmbientCO2 = (float)Math.Round(value * rawValueMult, decimalCount);

            measurement.UpdateIsDataWithinRange();
            if (!measurement.IsDataWithinRange)
            {
                LOG.Warning("values out of expected range.");
                return false;
            }
            return true;
        }

        public override string ToString()
        {
            return $"Environment inRange:{IsDataWithinRange} p:{Pressure} t:{Temperature} h:{Humidity}";
        }
    }
}
