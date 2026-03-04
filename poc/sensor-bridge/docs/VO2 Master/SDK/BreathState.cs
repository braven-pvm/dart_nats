using VO2MM.UI.Themes;
using Xamarin.Forms;

namespace VO2MM.IO.Devices.DeviceServices.VO2Master
{
    public enum BreathState
    {
        Inhale,
        None,
        Exhale
    }

    public static class BreathStateHelper
    {
        public static Color GetColor(this BreathState bs)
        {
            switch(bs)
            {
                case BreathState.Exhale: return Theme.VmColor;
                case BreathState.Inhale: return Color.Green;
                default: return Color.Transparent;
            };
        }

        public static string ToUiString(this BreathState bs)
        {
            switch(bs)
            {
                case BreathState.Exhale: return "Exhaling";
                case BreathState.Inhale: return "Inhaling";
                default: return "No breath";
            };
        }
    }
}
