using System;
using VO2MM.Common.Diagnostics;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master.V1_6
{
    public class VmVentilatoryMeasureV1_6
    {
        private static TaggedLog LOG = new TaggedLog(nameof(VmVentilatoryMeasureV1_6));

        public float Rf { get; private set; }
        public float Tv { get; private set; }
        public float Ve { get; private set; }
        public bool IsDataWithinRange { get; private set; }

        private void UpdateIsDataWithinRange()
        {
            IsDataWithinRange =
                Rf > 0 &&
                Rf < 100 &&
                Tv > 0 &&
                Tv < 10 &&
                Ve > 0 &&
                Ve < 500;
        }

        private const int decimalCount = 2;
        private const float rawValueMult = 0.01f;
        private const int byteGoalLength = 6;

        public static bool TryParse(byte[] bytes, out VmVentilatoryMeasureV1_6 measurement)
        {
            measurement = new VmVentilatoryMeasureV1_6();

            if (bytes == null || bytes.Length != byteGoalLength)
            {
                LOG.Warning($"unexpected byte length.");
                return false;
            }

            var value = BitConverter.ToUInt16(bytes, 0);
            measurement.Rf = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 2);
            measurement.Tv = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 4);
            measurement.Ve = (float)Math.Round(value * rawValueMult, decimalCount);
            
            measurement.UpdateIsDataWithinRange();
            if (measurement.IsDataWithinRange)
                return true;

            LOG.Warning($"values out of expected range.");
            return false;
        }

        public override string ToString()
        {
            return $"Ventilatory inRange:{IsDataWithinRange} rf:{Rf} tv:{Tv} ve:{Ve}";
        }
    }
}
