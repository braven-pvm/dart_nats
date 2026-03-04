using System;
using VO2MM.Common.Data;
using VO2MM.Common.Data.Units;
using VO2MM.Common.Diagnostics;
using VO2MM.Common.Util;
using VO2MM.IO.Bluetooth;
using VO2MM.Threading;
using VO2MM.Util;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master.V1_6
{
    public class VO2MasterParser_V1_6 : VO2MasterParserBase
    {
        private static TaggedLog LOG = new TaggedLog(nameof(VO2MasterParser_V1_6));

        public VO2MasterParser_V1_6(VO2MasterHandler handler) : base(handler)
        {

        }

        public override MeasurementType[] GetMeasurementTypes()
        {
            return measurementTypesO2Only;
        }

        //Use the timestamp from the latestVentilatoryMeasurementRow for all measurements. 
        //Assume firmware always sends all three at the same time, in the order ventilatory, gas exchangeµ, environment.
        private TimeSpan elapsedTimeDuringVentilatoryMeasurement;
        private VmVentilatoryMeasureV1_6 latestVentilatoryMeasurement;
        private VmGasExchangeMeasureV1_6 latestGasExchangeMeasurement;
        private VmEnvironmentMeasureV1_6 latestEnvironmentMeasurement;

        public override void OnHandleValue(BluetoothCharacteristicType dataType, byte[] data, float athleteWeight)
        {
            switch (dataType)
            {
                case BluetoothCharacteristicType.VO2MasterCommunicationOut:
                    {
                        //Data is always 4 in length due to characteristic size
                        if (data.Length != 4)
                            break;

                        var commandUint = data[0] | (data[1] << 8);
                        var command = EnumUtil.Convert(commandUint, VO2MasterDeviceCommandType.UnknownResponse);
                        var byvar = data[2] | (data[3] << 8);

                        ReceiveCommand(command, (ushort)byvar);
                    }
                    break;
                case BluetoothCharacteristicType.VO2MasterVentilatory:
                    {
                        if (!VmVentilatoryMeasureV1_6.TryParse(data, out VmVentilatoryMeasureV1_6 measure))
                        {
                            latestVentilatoryMeasurement = null;
                            return;
                        }

                        latestVentilatoryMeasurement = measure;

                        var batch = CreateMeasurementBatch();
                        elapsedTimeDuringVentilatoryMeasurement = batch.Time; //Use this for all three characteristics.
                        
                        batch.Add(MeasurementType.RespiratoryFrequency, latestVentilatoryMeasurement.Rf);
                        batch.Add(MeasurementType.TidalVolume, latestVentilatoryMeasurement.Tv);
                        batch.Add(MeasurementType.Ventilation, latestVentilatoryMeasurement.Ve);
                        RaiseMeasurementReceived(batch);
                    }
                    break;

                case BluetoothCharacteristicType.VO2MasterGasExchange:
                    {
                        if (!VmGasExchangeMeasureV1_6.TryParse(data, athleteWeight, out VmGasExchangeMeasureV1_6 measure))
                        {
                            latestGasExchangeMeasurement = null;
                            return;
                        }

                        latestGasExchangeMeasurement = measure;

                        var batch = CreateMeasurementBatch(elapsedTimeDuringVentilatoryMeasurement);
                        batch.Add(MeasurementType.FractionOfExpiredOxygen, latestGasExchangeMeasurement.FeO2);
                        batch.Add(MeasurementType.OxygenConsumption, latestGasExchangeMeasurement.VO2);
                        batch.Add(MeasurementType.OxygenConsumptionByWeight, latestGasExchangeMeasurement.VO2ByWeight);

                        RaiseMeasurementReceived(batch);
                    }
                    break;

                case BluetoothCharacteristicType.VO2MasterEnvironment:
                    {
                        if (!VmEnvironmentMeasureV1_6.TryParse(data, out VmEnvironmentMeasureV1_6 measure))
                        {
                            latestEnvironmentMeasurement = null;
                            return;
                        }

                        latestEnvironmentMeasurement = measure;

                        var batch = CreateMeasurementBatch(elapsedTimeDuringVentilatoryMeasurement);
                        batch.Add(MeasurementType.AmbientPressure, latestEnvironmentMeasurement.Pressure);
                        batch.Add(MeasurementType.FlowSensorTemp, latestEnvironmentMeasurement.Temperature);
                        batch.Add(MeasurementType.OxygenSensorHumidity, latestEnvironmentMeasurement.Humidity);

                        //The firmware should always update latestVentilatoryMeasurement just before gasExchange,
                        if (latestVentilatoryMeasurement != null &&
                            latestGasExchangeMeasurement != null &&
                            latestEnvironmentMeasurement != null &&
                            // Gas measurement should be in valid range
                            latestGasExchangeMeasurement.IsDataWithinRange)
                        {

                            CalculateEqO2(batch,
                                latestVentilatoryMeasurement.Ve,
                                latestGasExchangeMeasurement.VO2,
                                latestEnvironmentMeasurement.Pressure);
                        }

                        RaiseMeasurementReceived(batch);
                    }
                    break;

                case BluetoothCharacteristicType.VO2MasterGasCalbiration:
                    {
                        if (!VmGasCalibrationMeasureV1_6.TryParse(data, out VmGasCalibrationMeasureV1_6 measure))
                            return;

                        RecordDeviceDiagnostics(measure.ToString());
                    }
                    break;

                case BluetoothCharacteristicType.VO2MasterFlowCalbiration:
                    {
                        if (!VmSyringeCalibrationMeasureV1_6.TryParse(data, out VmSyringeCalibrationMeasureV1_6 measure))
                            return;

                        RecordDeviceDiagnostics(measure.ToString());
                    }
                    break;

            }
        }

       

        private BreathState lastBreathState = BreathState.None;
        private void ReceiveCommand(VO2MasterDeviceCommandType commandType, ushort value)
        {
            LOG.Verbose($"received command '{commandType}' value '{value}'");

            switch (commandType)
            {
                case VO2MasterDeviceCommandType.SetState:
                case VO2MasterDeviceCommandType.GetState:
                    {
                        VO2MasterDeviceState state = VO2MasterDeviceState.Idle;

                        const ushort isCalibratedMask = 0x10;
                        var isCalibrated = (value & isCalibratedMask) != 0;
                        state = EnumUtil.Convert(value & ~isCalibratedMask, VO2MasterDeviceState.Idle);

                        GasCalibInfo.IsCalibrated = isCalibrated;

                        if (state != VO2MasterDeviceState.CalibratingGas)
                            GasCalibInfo.CalibrationProgress = 0; //Reset stale calibration progress data.

                        RecordDeviceDiagnostics($"state:{state} isCalib:{isCalibrated}");

                        OnStateChanged(state);
                        NotifyUpdateGasCalibrationState();
                        NotifyUpdateFlowCalibrationState();
                    }
                    break;

                case VO2MasterDeviceCommandType.GetSubState:
                    {
                        var subState = EnumUtil.Convert(value, VO2MasterDeviceSubState.None);
                        OnSubStateChanged(subState);
                        RecordDeviceDiagnostics($"subState:{subState}");
                    }
                    break;
                case VO2MasterDeviceCommandType.GetSyringeProgress:
                    {
                        var breaths = (byte)value;
                        var total = value >> 8;
                        var progress = total == 0 ? 0d: (double)breaths / total;
                        progress = Math.Round(progress * 100);
                        progress = Math.Min(Math.Max(progress, 0), 100);
                        OnSyringeProgressChanged((float)progress);
                        NotifyUpdateFlowCalibrationState();

                        RecordDeviceDiagnostics($"syringeProgress:{progress} breaths:{breaths} total:{total}");
                    }
                    break;
                case VO2MasterDeviceCommandType.GetCalibrationProgress:
                    {
                        GasCalibInfo.CalibrationProgress = value;
                        NotifyUpdateGasCalibrationState();
                    }
                    break;
                case VO2MasterDeviceCommandType.GetVenturiSize:
                    {
                        var venturiSize = EnumUtil.Convert(value, VO2VenturiSize.Medium);
                        OnVenturiSizeChanged(venturiSize);
                        RecordDeviceDiagnostics($"ventureSize:{venturiSize}");
                    }
                    break;
                case VO2MasterDeviceCommandType.GetMaskSize:
                    {
                        var maskSize = EnumUtil.Convert(value, VO2MaskSize.Small);
                        OnMaskSizeChanged(maskSize);
                        RecordDeviceDiagnostics($"maskSize:{maskSize}");
                    }
                    break;
                case VO2MasterDeviceCommandType.GetIdleTimeoutMode:
                    {
                        var idleTimeoutMode = EnumUtil.Convert(value, VO2IdleTimeoutModes.Enabled);
                        OnIdleTimeoutModeChanged(idleTimeoutMode);
                    }
                    break;

                case VO2MasterDeviceCommandType.Error:
                    {
                        RaiseDeviceErrorReceived(value);
                    }
                    break;
                case VO2MasterDeviceCommandType.BreathStateChanged:
                    {
                        var bs = EnumUtil.Convert(value, BreathState.None);
                        if (bs == lastBreathState)
                            return; //Ignore duplicates

                        lastBreathState = bs;
                        OnBreathStateChanged(bs);
                    }
                    break;
                case VO2MasterDeviceCommandType.GetSyringeBreathCount:
                    {
                        if (value > 25 || value < 2)
                        {
                            RecordDeviceDiagnostics($"VM Syringe.BreathCount out of range: {value}");
                            break;
                        }
                        OnSyringeBreathCountChanged(value);
                    }
                    break;
                case VO2MasterDeviceCommandType.GetSyringeVolume:
                    {
                        var volume = value / 1000.0f;
                        if (float.IsNaN(volume) || volume < 0 || volume > 25)
                        {
                            RecordDeviceDiagnostics($"VM Syringe.Volume out of range: {volume}");
                            break;
                        }
                        OnSyringeVolumeChanged(volume);
                    }
                    break;
                case VO2MasterDeviceCommandType.GetSyringeFlags:
                    {
                        var flags = (VO2SyringeVenturiFlags)value;
                        OnSyringeFlagsChanged(flags);
                        NotifyUpdateFlowCalibrationState();
                    }
                    break;

            }
        }

        public override byte[] PrepCommand(VO2MasterDeviceCommandType command, ushort value = 0)
        {
            var commandInt = (ushort)command;

            return new[]
            {
                (byte)commandInt,
                (byte)(commandInt >> 8),
                (byte)value,
                (byte)(value >> 8)
            };
        }

        public override void SendInitialConnectionCommands(VO2MasterSettings settings)
        {
            //Set initial values from device settings
            SendCommand(VO2MasterDeviceCommandType.SetVenturiSize, (ushort)settings.VenturiSize);
            SendCommand(VO2MasterDeviceCommandType.SetMaskSize, (ushort)settings.MaskSize);
            SendCommand(VO2MasterDeviceCommandType.SetIdleTimeoutMode, (ushort)settings.IdleTimeoutMode);
            SendCommand(VO2MasterDeviceCommandType.SetSyringeBreathCount, (ushort)settings.SyringeBreathCount);
            SendCommand(VO2MasterDeviceCommandType.SetSyringeVolume, VmSyringeCalibrationMeasureV1_6.PrepareSyringeVolumeForTx(settings.SyringeGoalVolume));

            SendCommand(VO2MasterDeviceCommandType.GetState);
            SendCommand(VO2MasterDeviceCommandType.GetSubState);
            SendCommand(VO2MasterDeviceCommandType.GetGasCalibrationInfo);
            SendCommand(VO2MasterDeviceCommandType.GetSyringeProgress);
            SendCommand(VO2MasterDeviceCommandType.GetSyringeFlags);

        }

        public override void StartSyringeCalibration(int breathCount, float goalVolume)
        {
            SendCommand(VO2MasterDeviceCommandType.SetSyringeBreathCount, (ushort)breathCount);
            SendCommand(VO2MasterDeviceCommandType.SetSyringeVolume, VmSyringeCalibrationMeasureV1_6.PrepareSyringeVolumeForTx(goalVolume));
            SendCommand(VO2MasterDeviceCommandType.SetState, (ushort)VO2MasterDeviceState.CalibrateFlowSensor);
        }
    }
}
