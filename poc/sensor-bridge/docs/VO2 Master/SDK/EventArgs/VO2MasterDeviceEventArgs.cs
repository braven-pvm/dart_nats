using System;
using VO2MM.Common.Data;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master.EventArgs
{
    public class VO2MasterDeviceEventArgs : System.EventArgs
    {
        public VO2MasterDeviceEventArgs()
        {
        }
    }


    public class VO2MasterDeviceStateEventArgs : System.EventArgs
    {
        public VO2MasterDeviceStateEventArgs(VO2MasterDeviceState value)
        {
            Value = value;
        }

        public VO2MasterDeviceState Value { get; }
    }

    public class VO2MasterDeviceSubStateEventArgs : System.EventArgs
    {
        public VO2MasterDeviceSubStateEventArgs(VO2MasterDeviceSubState value)
        {
            Value = value;
        }

        public VO2MasterDeviceSubState Value { get; }
    }

    public class VO2MasterDeviceBreathStateEventArgs : System.EventArgs
    {
        public VO2MasterDeviceBreathStateEventArgs(BreathState value)
        {
            Value = value;
        }

        public BreathState Value { get; }
    }

    public class VO2MasterDeviceMaskSizeEventArgs : System.EventArgs
    {
        public VO2MasterDeviceMaskSizeEventArgs(VO2MaskSize value)
        {
            Value = value;
        }

        public VO2MaskSize Value { get; }
    }

    public class VO2MasterDeviceVenturiSizeEventArgs : System.EventArgs
    {
        public VO2MasterDeviceVenturiSizeEventArgs(VO2VenturiSize value)
        {
            Value = value;
        }

        public VO2VenturiSize Value { get; }
    }

    public class VO2MasterDeviceIdleTimeoutModeEventArgs : System.EventArgs
    {
        public VO2MasterDeviceIdleTimeoutModeEventArgs(VO2IdleTimeoutModes value)
        {
            Value = value;
        }

        public VO2IdleTimeoutModes Value { get; }
    }


    public class VO2MasterDeviceSyringeEventArgs : System.EventArgs
    {
        public VO2MasterDeviceSyringeEventArgs(int breathCount, float goalVolume, float progress, VO2SyringeVenturiFlags flags)
        {
            BreathCount = breathCount;
            GoalVolume = goalVolume;
            Progress = progress;
            Flags = flags;
        }

        public int BreathCount { get; }

        public float GoalVolume { get; }

        public VO2SyringeVenturiFlags Flags { get; }        

        public float Progress { get; }
    }


    public class VO2MasterDeviceErrorEventArgs : System.EventArgs
    {
        public VO2MasterDeviceErrorEventArgs(DeviceError error)
        {
            Value = error;
        }

        public DeviceError Value { get; }
    }

}
