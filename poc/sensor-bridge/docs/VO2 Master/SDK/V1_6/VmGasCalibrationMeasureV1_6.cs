using System;
using VO2MM.Common.Diagnostics;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master.V1_6
{
    public class VmGasCalibrationMeasureV1_6
    {
        private static TaggedLog LOG = new TaggedLog(nameof(VmGasCalibrationMeasureV1_6));

        public double AdcValue { get; private set; }
        public double AdcCoefficient { get; private set; }
        public float Pressure { get; private set; }
        public float Temperature { get; private set; }
        public float O2Thermistor { get; private set; }
        public float Humidity { get; private set; }

        public bool IsDataWithinRange { get; private set; }

        private const int decimalCount = 2;
        private const double rawValueMult = 0.01;
        private const int byteGoalLength = 12;

        private void UpdateIsDataWithinRange()
        {
            IsDataWithinRange =
                AdcValue >= 0 &&
                AdcValue <= 50000 &&
                AdcCoefficient >= 0 &&
                AdcCoefficient < 1000 &&
                Pressure >= 300 &&
                Pressure <= 1200 &&
                Temperature >= -25 &&
                Temperature <= 85 &&
                O2Thermistor >= -25 &&
                O2Thermistor <= 85 &&
                Humidity >= 0 &&
                Humidity <= 100;
        }

        public override string ToString()
        {
            return $"GasCalibration inRange:{IsDataWithinRange} adc:{AdcValue} o2Coef:{AdcCoefficient} p:{Pressure} t:{Temperature} therm:{O2Thermistor} h:{Humidity}";
        }

        public static bool TryParse(byte[] bytes, out VmGasCalibrationMeasureV1_6 measurement)
        {
            measurement = new VmGasCalibrationMeasureV1_6();

            if (bytes == null || bytes.Length != byteGoalLength)
            {
                LOG.Warning("unexpected byte length.");
                return false;
            }

            var value = BitConverter.ToUInt16(bytes, 0);
            measurement.AdcValue = value;
            value = BitConverter.ToUInt16(bytes, 2);
            measurement.AdcCoefficient = Math.Round(value * 0.000002, 8);
            value = BitConverter.ToUInt16(bytes, 4);
            measurement.Pressure = (float)Math.Round(value * 0.1, decimalCount);
            value = BitConverter.ToUInt16(bytes, 6);
            measurement.Temperature = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 8);
            measurement.O2Thermistor = (float)Math.Round(value * rawValueMult, decimalCount);
            value = BitConverter.ToUInt16(bytes, 10);
            measurement.Humidity = (float)Math.Round(value * rawValueMult, decimalCount);

            measurement.UpdateIsDataWithinRange();
            if (measurement.IsDataWithinRange)
                return true;

            LOG.Warning("values out of expected range.");
            return false;
        }
    }
}
