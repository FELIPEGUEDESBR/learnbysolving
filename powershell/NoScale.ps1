############
# This block of code forces the script to be DPI aware, to prevent scaling.

Add-Type -AssemblyName System.Runtime.InteropServices
$Null = [System.Runtime.InteropServices.Marshal]::PtrToStructure(
    [IntPtr]::Zero,
    [Type][System.IntPtr]
) # Ensures interop assembly loads properly

# Enable DPI awareness
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class DPI {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
[void][DPI]::SetProcessDPIAware()

############

$ErrorActionPreference = "SilentlyContinue"