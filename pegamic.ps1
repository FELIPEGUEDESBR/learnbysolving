Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class WaveInDevices
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct WAVEINCAPS
    {
        public ushort wMid;
        public ushort wPid;
        public uint vDriverVersion;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szPname;

        public uint dwFormats;
        public ushort wChannels;
        public ushort wReserved1;
        public uint dwSupport;
    }

    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    public static extern uint waveInGetNumDevs();

    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    public static extern uint waveInGetDevCaps(
        uint uDeviceID,
        out WAVEINCAPS pwic,
        uint cbwic
    );

    public static void List()
    {
        uint count = waveInGetNumDevs();

        Console.WriteLine("Dispositivos de captura encontrados: " + count);
        Console.WriteLine();

        for (uint i = 0; i < count; i++)
        {
            WAVEINCAPS caps;
            uint result = waveInGetDevCaps(
                i,
                out caps,
                (uint)Marshal.SizeOf(typeof(WAVEINCAPS))
            );

            if (result == 0)
            {
                Console.WriteLine("ID: " + i);
                Console.WriteLine("Nome: " + caps.szPname);
                Console.WriteLine("Canais: " + caps.wChannels);
                Console.WriteLine();
            }
            else
            {
                Console.WriteLine("ID: " + i + " - erro " + result);
            }
        }
    }
}
"@

[WaveInDevices]::List()
