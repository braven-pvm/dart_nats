using System;
using VO2MM.Common.Data;
using VO2MM.Common.Diagnostics;
using VO2MM.IO.Bluetooth;
using VO2MM.IO.Devices.DeviceServices.VO2Master.V1_3;
using VO2MM.IO.Devices.DeviceServices.VO2Master.V1_4;
using VO2MM.IO.Devices.DeviceServices.VO2Master.V1_5;
using VO2MM.Common.Util;
using VO2MM.Common.Data.Units;
using VO2MM.IO.Devices.DeviceServices.VO2Master.V1_6;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    public abstract class VO2MasterParserBase
    {
        public event EventHandler<VO2MasterDeviceState> StateChanged;
        public event EventHandler<VO2MasterDeviceSubState> SubStateChanged;
        public event EventHandler<BreathState> BreathStateChanged;
        public event EventHandler<VO2VenturiSize> VenturiSizeChanged;
        public event EventHandler<VO2MaskSize> MaskSizeChanged;
        public event EventHandler<VO2IdleTimeoutModes> IdleTimeoutModeChanged;
        public event EventHandler<int> SyringeBreathCountChanged;
        public event EventHandler<float> SyringeVolumeChanged;
        public event EventHandler<float> SyringeProgressChanged;
        public event EventHandler<VO2SyringeVenturiFlags> SyringeFlagsChanged;

        protected void OnStateChanged(VO2MasterDeviceState state)
        {
            StateChanged?.Invoke(this, state);
        }

        protected void OnSubStateChanged(VO2MasterDeviceSubState subState)
        {
            SubStateChanged?.Invoke(this, subState);
        }

        protected void OnBreathStateChanged(BreathState bs)
        {
            BreathStateChanged?.Invoke(this, bs);
        }

        protected void OnVenturiSizeChanged(VO2VenturiSize venturiSize)
        {
            VenturiSizeChanged?.Invoke(this, venturiSize);
        }

        protected void OnMaskSizeChanged(VO2MaskSize maskSize)
        {
            MaskSizeChanged?.Invoke(this, maskSize);
        }

        protected void OnIdleTimeoutModeChanged(VO2IdleTimeoutModes mode)
        {
            IdleTimeoutModeChanged?.Invoke(this, mode);
        }

        protected void OnSyringeBreathCountChanged(int count)
        {
            SyringeBreathCountChanged?.Invoke(this, count);
        }

        public void OnSyringeVolumeChanged(float volume)
        {
            SyringeVolumeChanged?.Invoke(this, volume);
        }

        public void OnSyringeProgressChanged(float progress)
        {
            SyringeProgressChanged?.Invoke(this, progress);
        }

        public void OnSyringeFlagsChanged(VO2SyringeVenturiFlags flags)
        {
            SyringeFlagsChanged?.Invoke(this, flags);
        }

        /// <summary>
        /// Get the version-specific parser.
        /// </summary>
        /// <param name="handler"></param>
        /// <param name="deviceVersion"></param>
        /// <returns></returns>
        public static VO2MasterParserBase Create(VO2MasterHandler handler, VO2MasterDeviceVersion deviceVersion)
        {
            switch (deviceVersion)
            {
                default:
                case VO2MasterDeviceVersion.Unknown:
                case VO2MasterDeviceVersion.BetaV2:
                case VO2MasterDeviceVersion.V1_0:
                case VO2MasterDeviceVersion.V1_2:
                case VO2MasterDeviceVersion.V1_3:
                case VO2MasterDeviceVersion.V1_4:
                case VO2MasterDeviceVersion.V1_5:
                    throw new ArgumentException();

                case VO2MasterDeviceVersion.V1_6:
                    return new VO2MasterParser_V1_6(handler);

            }
        }

        protected static readonly MeasurementType[] measurementTypesO2Only =
        {
            MeasurementType.RespiratoryFrequency,
            MeasurementType.TidalVolume,
            MeasurementType.Ventilation,
            MeasurementType.FractionOfExpiredOxygen,
            MeasurementType.OxygenConsumption,
            MeasurementType.OxygenConsumptionByWeight,
            MeasurementType.VentilationVO2,
            MeasurementType.EqO2,

            MeasurementType.FlowSensorTemp,
            MeasurementType.OxygenSensorHumidity,
            MeasurementType.AmbientPressure,
        };

        protected readonly VO2MasterHandler handler;

        public VO2MasterParserBase(VO2MasterHandler handler)
        {
            this.handler = handler;
            if (handler == null)
                throw new ArgumentNullException();
        }

        protected MeasurementValueBatch CreateMeasurementBatch(TimeSpan elapsedTime = default)
        {
            return handler.CreateMeasurementBatch(elapsedTime);
        }

        protected void RaiseMeasurementReceived(MeasurementValueBatch batch)
        {
            handler.RaiseMeasurementReceived(batch);
        }

        protected void SendCommand(VO2MasterDeviceCommandType command, ushort value = 0)
        {
            handler.SendCommand(command, value);
        }

        protected void NotifyUpdateGasCalibrationState()
        {
            handler.NotifyUpdateAmbientGasCalibrationState();
        }

        protected void NotifyUpdateFlowCalibrationState()
        {
            handler.NotifyUpdateFlowCalibrationState();
        }

        protected void RaiseDeviceErrorReceived(ushort errorCode)
        {
            var err = new DeviceError(errorCode);
            handler.RaiseDeviceErrorReceived(errorCode);

            Log.Debug($"VM Err: {err.ErrorCode}, {err.GetErrorDescription()}");
        }

        protected void RecordDeviceDiagnostics(string value)
        {
            if (string.IsNullOrEmpty(value))
                return;

            var err = new DeviceError(DeviceErrorConstants.DiagnositicError, value);
            handler.RaiseDeviceErrorReceived(err);

            Log.Debug(value);
        }

        protected VO2MasterDeviceGasCalibInfo GasCalibInfo => handler.GasCalibInfo;

        /// <summary>
        /// Get supported measurement types.
        /// </summary>
        /// <returns></returns>
        public abstract MeasurementType[] GetMeasurementTypes();
        /// <summary>
        /// Handle incoming BLE characteristic update.
        /// </summary>
        public abstract void OnHandleValue(BluetoothCharacteristicType dataType, byte[] data, float athleteWeight);
        /// <summary>
        /// Prepare bytes for transmission to device.
        /// </summary>
        /// <param name="command"></param>
        /// <param name="value"></param>
        /// <returns></returns>
        public abstract byte[] PrepCommand(VO2MasterDeviceCommandType command, ushort value = 0);
        /// <summary>
        /// Called upon connection established. Used to send initial configuration.
        /// <param name="settings"></param>
        /// </summary>
        public abstract void SendInitialConnectionCommands(VO2MasterSettings settings);
        /// <summary>
        /// Start a flow syringe calibration
        /// </summary>
        public abstract void StartSyringeCalibration(int breathCount, float goalVolume);



        protected void CalculateEqO2(MeasurementValueBatch batch, double ve, double vo2, double pressure)
        {
            try
            {
                if (!double.IsNaN(vo2) && Math.Abs(vo2) > double.Epsilon)
                {
                    var veStpd = EnviroHelper.ConvertBtpsToStpd(ve, pressure);
                    var eqO2 = veStpd / MeasurementUnitConverter.Millilitre.ToLitre(vo2);
                    batch.Add(MeasurementType.EqO2, (float) eqO2);
                }
            }
            catch(Exception ex)
            {
                Log.Error("failed to calculate EqO2", ex);
            }
        }
    }
}
