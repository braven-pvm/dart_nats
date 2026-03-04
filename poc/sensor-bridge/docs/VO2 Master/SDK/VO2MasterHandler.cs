using System;
using System.Threading.Tasks;
using VO2MM.Common.Data;
using VO2MM.Common.Diagnostics;
using VO2MM.Data;
using VO2MM.IO.Bluetooth;
using VO2MM.IO.Devices.DeviceServices.VO2Master.EventArgs;
using VO2MM.Threading;
using VO2MM.UI.Message;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    public class VO2MasterHandler : BaseBluetoothHandler<VO2MasterSettings>
    {
        private static readonly TimeSpan SEND_DELAY = TimeSpan.FromMilliseconds(200);
        private static readonly TimeSpan SHORT_SEND_DELAY = TimeSpan.FromMilliseconds(25);
        

        public readonly VO2MasterDeviceVersion DeviceVersion = VO2MasterDeviceVersion.Unknown;

        private bool serviceReady = false;

        private readonly VO2MasterParserBase parser;

        private readonly Vo2MasterBlackListHelper blackListHelper = new Vo2MasterBlackListHelper();


        //All available characteristic types, can include those not present in certain device variants.
        public VO2MasterHandler(IBluetoothDevice device, IBluetoothService serviceInstance, IDeviceServiceHandlerListener listener) :
			base("VO2 Master Analyzer", device, serviceInstance, listener, false,
                BluetoothCharacteristicType.VO2MasterCommunicationIn,
                BluetoothCharacteristicType.VO2MasterCommunicationOut,
                BluetoothCharacteristicType.VO2MasterDataMeasurement,
                BluetoothCharacteristicType.VO2MasterVentilatory,
                BluetoothCharacteristicType.VO2MasterGasExchange,
                BluetoothCharacteristicType.VO2MasterEnvironment,
                BluetoothCharacteristicType.VO2MasterGasCalbiration,
                BluetoothCharacteristicType.VO2MasterFlowCalbiration,
                )
        {
            if (Device == null || Device.Information == null)
            {
                //It is assumed that Device.Information is populated
                throw new Exception("DeviceInformation ModelNumber not ready for VO2MasterHandler");
            }

            //Set device version once Device.Information is populated.
            DeviceVersion = VO2MasterDeviceVersionHelper.TryGetVersionFromModelNumber(Device.Information.ModelNumber);
            Log.Debug("Fetched new VO2 Master device version: {0}", DeviceVersion);

            //Instantiate version-specifc parser / transmitter
            parser = VO2MasterParserBase.Create(this, DeviceVersion);
            parser.StateChanged += OnParserStateChanged;
            parser.SubStateChanged += OnParserSubStateChanged;
            parser.BreathStateChanged += OnParserBreathStateChanged;
            parser.VenturiSizeChanged += OnParserVenturiSizeChanged;
            parser.MaskSizeChanged += OnParserMaskSizeChanged;
            parser.IdleTimeoutModeChanged += OnParserIdleTimeoutModeChanged;
            parser.SyringeBreathCountChanged += OnParserSyringeBreathCountChanged;
            parser.SyringeVolumeChanged += OnParserSyringeVolumeChanged;
            parser.SyringeProgressChanged += OnParserSyringeProgressChanged;
            parser.SyringeFlagsChanged += OnParserSyringeFlagsChanged;

            //Set initial values from device settings
            var settings = GetServiceSettings();
            VenturiSize = settings.VenturiSize;
            MaskSize = settings.MaskSize;
            IdleTimeoutMode = settings.IdleTimeoutMode;
            SyringeBreathCount = settings.SyringeBreathCount;
            SyringeGoalVolume = settings.SyringeGoalVolume;
        }

        public event EventHandler<VO2MasterDeviceStateEventArgs> StateChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceSubStateEventArgs> SubStateChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceBreathStateEventArgs> BreathStateChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceVenturiSizeEventArgs> VenturiSizeChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceMaskSizeEventArgs> MaskSizeChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceIdleTimeoutModeEventArgs> IdleTimeoutModeChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceSyringeEventArgs> SyringeBreathCountChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceSyringeEventArgs> SyringeGoalVolumeChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceSyringeEventArgs> SyringeProgressChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceSyringeEventArgs> SyringeFlagsChanged
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }

        public event EventHandler<VO2MasterDeviceErrorEventArgs> ReceivedVO2DeviceError
        {
            add => eventManager.AddEventHandler(value);
            remove => eventManager.RemoveEventHandler(value);
        }


        private void OnParserStateChanged(object sender, VO2MasterDeviceState e)
        {
            State = e;
            RaiseEvent(new VO2MasterDeviceStateEventArgs(State), nameof(StateChanged), true);
        }

        private void OnParserSubStateChanged(object sender, VO2MasterDeviceSubState e)
        {
            SubState = e;
            RaiseEvent(new VO2MasterDeviceSubStateEventArgs(SubState), nameof(SubStateChanged), true);
        }

        private void OnParserBreathStateChanged(object sender, BreathState e)
        {
            BreathState = e;
            RaiseEvent(new VO2MasterDeviceBreathStateEventArgs(BreathState), nameof(BreathStateChanged), true);            
        }

        private void OnParserVenturiSizeChanged(object sender, VO2VenturiSize e)
        {
            VenturiSize = e;
            RaiseEvent(new VO2MasterDeviceVenturiSizeEventArgs(VenturiSize), nameof(VenturiSizeChanged), true);            
        }

        private void OnParserMaskSizeChanged(object sender, VO2MaskSize e)
        {
            MaskSize = e;
            RaiseEvent(new VO2MasterDeviceMaskSizeEventArgs(MaskSize), nameof(MaskSizeChanged), true);            
        }

        private void OnParserIdleTimeoutModeChanged(object sender, VO2IdleTimeoutModes e)
        {
            IdleTimeoutMode = e;
            RaiseEvent(new VO2MasterDeviceIdleTimeoutModeEventArgs(IdleTimeoutMode), nameof(IdleTimeoutModeChanged), true);            
        }

        private void OnParserSyringeBreathCountChanged(object sender, int e)
        {
            SyringeBreathCount = e;
            RaiseEvent(new VO2MasterDeviceSyringeEventArgs(SyringeBreathCount, SyringeGoalVolume, SyringeProgress, SyringeFlags), nameof(SyringeBreathCountChanged), true);            
        }

        private void OnParserSyringeVolumeChanged(object sender, float e)
        {
            SyringeGoalVolume = e;            
            RaiseEvent(new VO2MasterDeviceSyringeEventArgs(SyringeBreathCount, SyringeGoalVolume, SyringeProgress, SyringeFlags), nameof(SyringeGoalVolumeChanged), true);
        }

        private void OnParserSyringeProgressChanged(object sender, float e)
        {
            SyringeProgress = e;            
            RaiseEvent(new VO2MasterDeviceSyringeEventArgs(SyringeBreathCount, SyringeGoalVolume, SyringeProgress, SyringeFlags), nameof(SyringeProgressChanged), true);
        }

        private void OnParserSyringeFlagsChanged(object sender, VO2SyringeVenturiFlags e)
        {
            SyringeFlags = e;            
            RaiseEvent(new VO2MasterDeviceSyringeEventArgs(SyringeBreathCount, SyringeGoalVolume, SyringeProgress, SyringeFlags), nameof(SyringeFlagsChanged), true);
        }

        public override void RaiseDeviceErrorReceived(int errorCode)
        {
            base.RaiseDeviceErrorReceived(errorCode);
            RaiseEvent(new VO2MasterDeviceErrorEventArgs(new DeviceError(errorCode)), nameof(ReceivedVO2DeviceError), true);
        }

        public override MeasurementType[] MeasurementTypes
        { get { return parser.GetMeasurementTypes(); } }

        public VO2MasterDeviceState State
        { get; private set; }

        public VO2MasterDeviceSubState SubState
        { get; private set; }

        public BreathState BreathState
        { get; private set; } = BreathState.None;

        public VO2SyringeVenturiFlags SyringeFlags
        { get; private set; }

        public float SyringeProgress
        { get; private set; }

        private VO2VenturiSize _venturiSize;
        public VO2VenturiSize VenturiSize
        {
            get { return _venturiSize; }
            private set
            {
                if (_venturiSize != value)
                {
                    _venturiSize = value;
                    GetServiceSettings().VenturiSize = value;
                }
            }
        }

        private VO2MaskSize _maskSize;
        public VO2MaskSize MaskSize
        {
            get { return _maskSize; }
            private set
            {
                if (_maskSize != value)
                {
                    _maskSize = value;
                    GetServiceSettings().MaskSize = value;
                }
            }
        }

        private VO2IdleTimeoutModes _idleTimeoutMode;
        public VO2IdleTimeoutModes IdleTimeoutMode
        {
            get { return _idleTimeoutMode; }
            private set
            {
                if (_idleTimeoutMode != value)
                {
                    _idleTimeoutMode = value;
                    GetServiceSettings().IdleTimeoutMode = value;
                }
            }
        }

        private int _syringeBreathCount;
        public int SyringeBreathCount
        {
            get { return _syringeBreathCount; }
            private set
            {
                if (_syringeBreathCount != value)
                {
                    _syringeBreathCount = value;
                    GetServiceSettings().SyringeBreathCount = value;
                }
            }
        }

        private float _syringeGoalVolume;
        public float SyringeGoalVolume
        {
            get { return _syringeGoalVolume; }
            private set
            {
                if (_syringeGoalVolume != value)
                {
                    _syringeGoalVolume = value;
                    GetServiceSettings().SyringeGoalVolume = value;
                }
            }
        }

        private void StartSyringeCalibration(int breathCount, float volume)
        {
            SyringeBreathCount = breathCount;
            SyringeGoalVolume = volume;
            parser.StartSyringeCalibration(SyringeBreathCount, SyringeGoalVolume);
        }

        public void BeginOneLitreSyringeCalibration()
        {
            StartSyringeCalibration(10, 1.0f);
        }

        public void BeginThreeLitreSyringeCalibration()
        {
            StartSyringeCalibration(10, 3.0f);
        }

        /// <summary>
        /// Latest calibration method from device. Should never be null.
        /// </summary>
        public VO2MasterDeviceGasCalibInfo GasCalibInfo
        { get; private set; } = new VO2MasterDeviceGasCalibInfo();

        public string GetAmbientGasCalibrationProgressString()
        {
            return GasCalibInfo.GetGasCalibrationProgressString();
        }

        public string GetFlowCalibrationProgressString()
        {
            return $"Flow Calibration: {SyringeProgress}%";
        }

        public void NotifyUpdateAmbientGasCalibrationState()
        {
            ThreadHelper.RunOnMainThread(() =>
            {
                MessageHelper.Send(new VO2GasCalibrationEvent(GasCalibInfo), this);
            });
        }

        public void NotifyUpdateFlowCalibrationState()
        {
            ThreadHelper.RunOnMainThread(() =>
            {
                MessageHelper.Send(new VO2FlowCalibrationEvent(IsSyringeCalibrated, SyringeProgress), this);
            });
        }

        public bool IsCalibratingAmbientGas
        {
            get { return State == VO2MasterDeviceState.CalibratingGas; }
        }

        public bool IsAmbientGasCalibrated
        {
            get { return GasCalibInfo.IsCalibrated || State == VO2MasterDeviceState.Recording; }
        }

        public bool IsCalibratingSyringe
        {
            get { return State == VO2MasterDeviceState.CalibrateFlowSensor; }
        }

        public bool IsSyringeCalibrated
        {
            get { return State != VO2MasterDeviceState.CalibrateFlowSensor && SyringeFlags.HasFlag(VenturiSize.GetSyringeFlag()); }
        }

        private void SetStateCalibrateAmbientGas()
        {
            SendCommand(VO2MasterDeviceCommandType.SetState, (byte)VO2MasterDeviceState.CalibratingGas);
        }

        private void SetStateRecord()
        {
            SendCommand(VO2MasterDeviceCommandType.SetState, (byte)VO2MasterDeviceState.Recording);
        }

        /// <summary>
        /// Ensures the device is not in syringe calibration mode.
        /// If it is, state is switched to gas calibration, if calibration is incomplete.
        /// Otherwise state is switched to Record.
        /// This is useful to call after cancelling syringe calibration,
        /// or just before starting a recording.
        /// </summary>
        public void EnsureNotStuckInSyringeCalibrationState()
        {
            if (State != VO2MasterDeviceState.CalibrateFlowSensor)
                return;
            
            if (IsAmbientGasCalibrated)
                SetStateRecord();
            else
                SetStateCalibrateAmbientGas();
        }

        private IBluetoothCharacteristic deviceComInputCharacteristic;

        public void SendCommand(VO2MasterDeviceCommandType command, ushort value = 0)
        {
            if (IsDisposed || Device.IsDisconnected)
                return;

            // Firmware input is our output          
            if (deviceComInputCharacteristic == null)
            {
                Log.Error("VO2Master: communication input is null");
                return;
            }

            if (!serviceReady)
            {
                //wait a short time before any send upon connect.
                Task.Delay(SEND_DELAY).Wait();
                serviceReady = true;
            }
            
            var bytes = parser.PrepCommand(command, value);
            if (bytes == null) return;

            deviceComInputCharacteristic.WriteValue(bytes);

            //always wait a short amount of time, avoid overwriting the send buffer when send multiple commands in sequence
            Task.Delay(SHORT_SEND_DELAY).Wait();

            Log.Verbose($"'{nameof(VO2MasterHandler)}': send command '{command}' value '{value}' to '{Device.DisplayName}'");
        }

        protected override void OnBluetoothCharacteristicDiscovered(IBluetoothCharacteristic characteristic)
        {
            base.OnBluetoothCharacteristicDiscovered(characteristic);

            if (characteristic.Type == BluetoothCharacteristicType.VO2MasterCommunicationIn)
                deviceComInputCharacteristic = characteristic;
        }

        public void RequestAmbientGasRecalibration()
        {
            SendCommand(VO2MasterDeviceCommandType.SetState, (ushort)VO2MasterDeviceState.CalibratingGas);
        }

        public void RequestFlowRecalibration()
        {
            SendCommand(VO2MasterDeviceCommandType.SetState, (ushort)VO2MasterDeviceState.CalibrateFlowSensor);
        }

        public void SendDFUModeCommand()
        {
            SendCommand(VO2MasterDeviceCommandType.RequestEnterDfuMode);

            var deviceBle = (IBluetoothDevice)Device;
            if (deviceBle != null && deviceBle.Peripheral != null && deviceBle.Peripheral.AdvertisedData != null)
            {
                deviceBle.Peripheral.AdvertisedData.Expire();
            }
        }

        //Change settings in order to send VO2 Master Analyzer commands.
        public override bool OnSettingsUpdated(IDeviceSetting value)
        {
            base.OnSettingsUpdated(value);

            if (!(value is VO2MasterSettings))
                return false;
            
            var settings = value as VO2MasterSettings;
            //send the new values to the device
            if (settings.VenturiSize != VenturiSize)
            {
                VenturiSize = settings.VenturiSize;
                SendCommand(VO2MasterDeviceCommandType.SetVenturiSize, (byte)settings.VenturiSize);
            }
            if (settings.MaskSize != MaskSize)
            {
                MaskSize = settings.MaskSize;
                SendCommand(VO2MasterDeviceCommandType.SetMaskSize, (byte)settings.MaskSize);
            }
            if (settings.IdleTimeoutMode != IdleTimeoutMode)
            {
                IdleTimeoutMode = settings.IdleTimeoutMode;
                SendCommand(VO2MasterDeviceCommandType.SetIdleTimeoutMode, (byte)settings.IdleTimeoutMode);
            }

            return true;
        }

        protected override void OnHandleValue(BluetoothCharacteristicType dataType, byte[] data)
        {
            if (IsDisposed || !Enabled)
                return;

            //Ensure device is not stolen
            if (Device != null && blackListHelper.IsBlackListed(Device.Information))
                return;

            var session = CurrentSession;
            float weightKg = 0;
            if (session != null && session.AthleteForSession != null)
                weightKg = session.AthleteForSession.WeightKilograms;

            parser.OnHandleValue(dataType, data, weightKg);
        }

        protected override void OnHandleSubscriptionChanged(IBluetoothCharacteristic characteristic)
        {
            base.OnHandleSubscriptionChanged(characteristic);

            if (characteristic == null ||
                !characteristic.IsNotifying ||
                characteristic.Type != BluetoothCharacteristicType.VO2MasterCommunicationOut) return;

            Log.Verbose($"'{nameof(VO2MasterHandler)}': bluetooth communication established");
            var settings = GetServiceSettings();
            parser.SendInitialConnectionCommands(settings);
        }

        protected override void OnDispose(bool disposing)
        {
            base.OnDispose(disposing);

            NotifyUpdateAmbientGasCalibrationState();
            NotifyUpdateFlowCalibrationState();
            serviceReady = false;
            deviceComInputCharacteristic = null;
        }
    }
}
