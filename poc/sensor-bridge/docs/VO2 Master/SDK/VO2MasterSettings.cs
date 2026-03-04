using Newtonsoft.Json;
using VO2MM.Data;
using VO2MM.Common.Data;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    public class VO2MasterSettings : BaseDeviceServiceSettings
	{
		public VO2MasterSettings()
		{

        }

        [JsonIgnore]
        public VO2VenturiSize VenturiSize
        {
            get
            {
                var config = ConfigurationManager.Current;
                if (config != null)
                    return config.VenturiSize;
                else
                    return VO2VenturiSize.Medium;
            }
            set
            {
				var config = ConfigurationManager.Current;
                if (config != null)
                    config.VenturiSize = value;
            }
        }

        [JsonIgnore]
        public VO2MaskSize MaskSize
        {
            get
            {
                var config = ConfigurationManager.Current;
                if (config != null)
                    return config.MaskSize;
                else
                    return VO2MaskSize.Small;
            }
            set
            {
                var config = ConfigurationManager.Current;
                if (config != null)
                    config.MaskSize = value;
            }
        }

        [JsonIgnore]
        public VO2IdleTimeoutModes IdleTimeoutMode
        {
            get
            {
                var config = ConfigurationManager.Current;
                if (config != null)
                    return config.IdleTimeoutMode;
                else
                    return VO2IdleTimeoutModes.Enabled;
            }
            set
            {
                var config = ConfigurationManager.Current;
                if (config != null)
                    config.IdleTimeoutMode = value;
            }
        }

        [JsonIgnore]
        public int SyringeBreathCount
        {
            get
            {
                var config = ConfigurationManager.Current;
                if (config == null)
                    return 0;
                else
                    return config.SyringeBreathCount;
            }
            set
            {
                var config = ConfigurationManager.Current;
                if (config != null)
                    config.SyringeBreathCount = value;
            }
        }

        [JsonIgnore]
        public float SyringeGoalVolume
        {
            get
            {
                var config = ConfigurationManager.Current;
                if (config == null)
                    return 0;
                else
                    return config.SyringeGoalVolume;
            }
            set
            {
                var config = ConfigurationManager.Current;
                if (config != null)
                    config.SyringeGoalVolume = value;
            }
        }
    }
}
