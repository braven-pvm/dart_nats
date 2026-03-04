using System.Collections.Generic;
using VO2MM.Common.Data;

namespace VO2MM.IO.Devices
{
    /// <summary>
    /// Helper class that provides UI display information for VO2 Master Analyzer error codes.
    /// Last updated: Nov 27, 2020
    /// </summary>
    public static class VO2MasterErrorCodeHelper
    {
        private const int FatalErrorOffset = 0;             //Offset for fatal errors.
        private const int WarningErrorOffset = 50;          //Offset for warnings errors.
        private const int DiagnosticErrorOffset = 120;      //Offset for diagnostic errors. These are not reported to the user but are recorded.

        /// <summary>
        /// Returns the DeviceErrorLevel for a given error code.
        /// </summary>
        /// <param name="error"></param>
        /// <returns></returns>
        public static DeviceErrorLevel GetErrorLevel(this DeviceError error)
        {
            if (error == null) return DeviceErrorLevel.None;

            if (error.ErrorCode < WarningErrorOffset)
                return DeviceErrorLevel.Fatal;
            if (error.ErrorCode < DiagnosticErrorOffset)
                return DeviceErrorLevel.Warning;

            return DeviceErrorLevel.Diagnositic;
        }

        /// <summary>
        /// The header text to display for an error code
        /// </summary>
        /// <param name="error"></param>
        /// <returns></returns>
        public static string GetErrorHeader(this DeviceError error)
        {
            if (error == null) return string.Empty;

            if (error.ErrorCode < WarningErrorOffset)
                return "Fatal Error";
            if (error.ErrorCode < DiagnosticErrorOffset)
                return "Warning";

            return "Diagnostic Message";
        }

        /// <summary>
        /// Returns the display option for the given error code.
        /// </summary>
        /// <param name="error"></param>
        /// <returns></returns>
        public static DeviceErrorDisplayOptions GetErrorDisplayOption(this DeviceError error)
        {
            if (error == null || !error.HasDescription() || error.DoHideFromUi()) return DeviceErrorDisplayOptions.None;

            switch (error.GetErrorLevel())
            {
                case DeviceErrorLevel.Fatal: return DeviceErrorDisplayOptions.DismissableAlert;
                case DeviceErrorLevel.Warning: return DeviceErrorDisplayOptions.SubtleAlert;
                default: return DeviceErrorDisplayOptions.None;
            };
        }

        /// <summary>
        /// Returns true if the given error code should be hidden from UI display even if it's a warning or fatal error.
        /// </summary>
        /// <param name="errorCode"></param>
        /// <returns></returns>
        public static bool DoHideFromUi(this DeviceError error)
        {
            switch (error.ErrorCode)
            {
                //Ventilation out of range.
                case (WarningErrorOffset + 14): return true;
                default: return false;
            };
        }

        /// <summary>
        /// Returns whether the given error code has a unique description.
        /// </summary>
        /// <param name="error"></param>
        /// <returns></returns>
        public static bool HasDescription(this DeviceError error)
        {
            if (error == null) return false;
            return errorCodeDescriptions.ContainsKey(error.ErrorCode);
        }

        /// <summary>
        /// Gets the description for the given DeviceError.Code.
        /// If no description is available, returns generic string with error code.
        /// </summary>
        /// <param name="error"></param>
        /// <returns></returns>
        public static string GetErrorDescription(this DeviceError error)
        {
            if (error == null) return string.Empty;
            return GetErrorDescription(error.ErrorCode);
        }

        /// <summary>
        /// Gets the description for the given errorCode.
        /// If no description is available, returns generic string with error code.
        /// </summary>
        /// <param name="errorCode"></param>
        /// <returns></returns>
        public static string GetErrorDescription(int errorCode)
        {
            if (errorCodeDescriptions.ContainsKey(errorCode))
                return errorCodeDescriptions[errorCode];

            return "Error Code: " + errorCode;
        }

        /// <summary>
        /// Holds all error codes of potential interest to the user. Error codes not included in this list will still be logged in a data table.
        /// </summary>
        private static readonly Dictionary<int, string> errorCodeDescriptions = new Dictionary<int, string>
        {
            //Fatal errors
            { FatalErrorOffset + 1, "Initialization error, shutting off." },
            { FatalErrorOffset + 2, "Too hot, shutting off." },
            { FatalErrorOffset + 3, "Too cold, shutting off." },
            { FatalErrorOffset + 4, "Sat idle too long, shutting off." },
            { FatalErrorOffset + 5, "Battery is out of charge, shutting off." },
            { FatalErrorOffset + 6, "Battery is out of charge, shutting off." },
            { FatalErrorOffset + 7, "Battery is out of charge, shutting off." },
            { FatalErrorOffset + 8, "Failed to initialize environmental sensor." },
            { FatalErrorOffset + 9, "Failed to initialize oxygen sensor." },
            { FatalErrorOffset + 10, "Failed to initialize flow sensor." },
            { FatalErrorOffset + 11, "Failed to initialize sensor communication." },
            { FatalErrorOffset + 12, "Flast memory error." },
            { FatalErrorOffset + 13, "Flast memory error." },
            { FatalErrorOffset + 14, "CO2 sensor disconnected." },
            { FatalErrorOffset + 15, "Test failed." },
            { FatalErrorOffset + 16, "O2 sensor thermistor disconnected." },
            { FatalErrorOffset + 17, "O2 sensor thermistor disconnected." },

            //Warnings
            { WarningErrorOffset + 4,  "Analyzer is very hot." },
            { WarningErrorOffset + 5,  "Analyzer is very cold." },
            { WarningErrorOffset + 7,  "Oxygen sensor too humid." },
            { WarningErrorOffset + 8, "Oxygen sensor was too humid and has now dried." },
            { WarningErrorOffset + 9, "Remove analyzer or hold your breath for at least 10 seconds\n to complete flow sensor zero-offset calibration." },
            { WarningErrorOffset + 11, "Low battery." },
            { WarningErrorOffset + 14, "Ventilation out of range." },
            { WarningErrorOffset + 21, "Humidity at the gas sensors is approaching a dangerous level." },
            { WarningErrorOffset + 22, "Pump has been disabled for a long time, signifying a potential issue." },

            //Diagnostics
            { DiagnosticErrorOffset + 0,  "Calibration: waiting for user to start breathing." },
            { DiagnosticErrorOffset + 1,  "Breath rejected: too jittery." },
            { DiagnosticErrorOffset + 2,  "Breath rejected: segment too short." },
            { DiagnosticErrorOffset + 3,  "Breath rejected: breath too short." },
            { DiagnosticErrorOffset + 4,  "Breath rejected: breath too small." },
            { DiagnosticErrorOffset + 5,  "Breath rejected: Rf out of range." },
            { DiagnosticErrorOffset + 6,  "Breath rejected: Tv out of range." },
            { DiagnosticErrorOffset + 7,  "Breath rejected: Ve out of range." },
            { DiagnosticErrorOffset + 8,  "Breath rejected: FeO2 out of range." },
            { DiagnosticErrorOffset + 9,  "Breath rejected: VO2 out of range." },
            { DiagnosticErrorOffset + 10,  "Analyzer initialized." },
            { DiagnosticErrorOffset + 12,  "Oxygen sensor calibration waveform is volatile." },
            { DiagnosticErrorOffset + 29,  "User turned off device with power button." },
            { DiagnosticErrorOffset + 40,  "Breath rejected: FeCO2 out of range." },
            { DiagnosticErrorOffset + 41,  "Breath rejected: VCO2 out of range." },
            { DiagnosticErrorOffset + 50,  "Breath rejected: RER out of range." },
            { DiagnosticErrorOffset + 76,  "Breath rejected: Rf out of range." },
            { DiagnosticErrorOffset + 77,  "Breath rejected: Tv out of range." },

            { DeviceErrorConstants.DiagnositicError,  "Info" }, // Diagnostic values created by the app 
        };
    }
}
