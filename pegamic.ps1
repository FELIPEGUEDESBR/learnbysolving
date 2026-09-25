# ============================================================
# STREAM DE MICROFONE - POWERSHELL + .NET
#
# Captura:
#   16 kHz
#   16 bits
#   Mono
#
# Envia:
#   TCP
#
# Destino:
#   servidor Whisper
# ============================================================


# ------------------------------------------------------------
# CONFIGURAÇÃO
# ------------------------------------------------------------

$Servidor = "192.168.0.12"
$Porta = 5000

$SampleRate = 16000
$Bits = 16
$Channels = 1


# ------------------------------------------------------------
# CÓDIGO .NET PARA CAPTURA DO MICROFONE
# ------------------------------------------------------------

Add-Type @"

using System;
using System.Runtime.InteropServices;

public class MicrophoneCapture
{
    private const int CALLBACK_FUNCTION = 0x00030000;
    private const int WIM_OPEN = 0x3BE;
    private const int WIM_DATA = 0x3C0;
    private const int WIM_CLOSE = 0x3BF;

    private const int WAVE_FORMAT_PCM = 1;

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEFORMATEX
    {
        public ushort wFormatTag;
        public ushort nChannels;
        public uint nSamplesPerSec;
        public uint nAvgBytesPerSec;
        public ushort nBlockAlign;
        public ushort wBitsPerSample;
        public ushort cbSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEHDR
    {
        public IntPtr lpData;
        public uint dwBufferLength;
        public uint dwBytesRecorded;
        public IntPtr dwUser;
        public uint dwFlags;
        public uint dwLoops;
        public IntPtr lpNext;
        public IntPtr reserved;
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate void WaveInProc(
        IntPtr hwi,
        uint uMsg,
        IntPtr dwInstance,
        IntPtr dwParam1,
        IntPtr dwParam2
    );

    [DllImport("winmm.dll")]
    private static extern int waveInOpen(
        out IntPtr phwi,
        int uDeviceID,
        ref WAVEFORMATEX pwfx,
        WaveInProc dwCallback,
        IntPtr dwInstance,
        int fdwOpen
    );

    [DllImport("winmm.dll")]
    private static extern int waveInPrepareHeader(
        IntPtr hwi,
        IntPtr pwh,
        int cbwh
    );

    [DllImport("winmm.dll")]
    private static extern int waveInAddBuffer(
        IntPtr hwi,
        IntPtr pwh,
        int cbwh
    );

    [DllImport("winmm.dll")]
    private static extern int waveInStart(
        IntPtr hwi
    );

    [DllImport("winmm.dll")]
    private static extern int waveInStop(
        IntPtr hwi
    );

    [DllImport("winmm.dll")]
    private static extern int waveInReset(
        IntPtr hwi
    );

    [DllImport("winmm.dll")]
    private static extern int waveInUnprepareHeader(
        IntPtr hwi,
        IntPtr pwh,
        int cbwh
    );

    [DllImport("winmm.dll")]
    private static extern int waveInClose(
        IntPtr hwi
    );


    private IntPtr hWaveIn = IntPtr.Zero;

    private WaveInProc callback;

    private IntPtr[] headers;

    private IntPtr[] buffers;

    public event Action<byte[]> DataAvailable;


    public void Start(
        int sampleRate,
        short channels,
        short bits
    )
    {

        WAVEFORMATEX format = new WAVEFORMATEX();

        format.wFormatTag = WAVE_FORMAT_PCM;

        format.nChannels = channels;

        format.nSamplesPerSec = (uint)sampleRate;

        format.wBitsPerSample = bits;

        format.nBlockAlign =
            (ushort)(channels * bits / 8);

        format.nAvgBytesPerSec =
            (uint)(sampleRate *
                   format.nBlockAlign);

        format.cbSize = 0;


        callback = WaveCallback;


        int result = waveInOpen(
            out hWaveIn,
            -1,
            ref format,
            callback,
            IntPtr.Zero,
            CALLBACK_FUNCTION
        );


        if (result != 0)
        {
            throw new Exception(
                "Não foi possível abrir o microfone. Código: "
                + result
            );
        }


        int bufferCount = 4;

        int bufferSize =
            sampleRate *
            channels *
            bits / 8 / 2;


        headers =
            new IntPtr[bufferCount];

        buffers =
            new IntPtr[bufferCount];


        for (int i = 0; i < bufferCount; i++)
        {

            buffers[i] =
                Marshal.AllocHGlobal(
                    bufferSize
                );


            WAVEHDR header =
                new WAVEHDR();

            header.lpData =
                buffers[i];

            header.dwBufferLength =
                (uint)bufferSize;


            headers[i] =
                Marshal.AllocHGlobal(
                    Marshal.SizeOf<WAVEHDR>()
                );


            Marshal.StructureToPtr(
                header,
                headers[i],
                false
            );


            waveInPrepareHeader(
                hWaveIn,
                headers[i],
                Marshal.SizeOf<WAVEHDR>()
            );


            waveInAddBuffer(
                hWaveIn,
                headers[i],
                Marshal.SizeOf<WAVEHDR>()
            );
        }


        waveInStart(hWaveIn);
    }


    private void WaveCallback(
        IntPtr hwi,
        uint message,
        IntPtr instance,
        IntPtr param1,
        IntPtr param2
    )
    {

        if (message != WIM_DATA)
            return;


        WAVEHDR header =
            Marshal.PtrToStructure<WAVEHDR>(
                param1
            );


        if (header.dwBytesRecorded > 0)
        {

            byte[] audio =
                new byte[
                    header.dwBytesRecorded
                ];


            Marshal.Copy(
                header.lpData,
                audio,
                0,
                (int)header.dwBytesRecorded
            );


            DataAvailable?.Invoke(audio);
        }


        waveInAddBuffer(
            hWaveIn,
            param1,
            Marshal.SizeOf<WAVEHDR>()
        );
    }


    public void Stop()
    {

        if (hWaveIn == IntPtr.Zero)
            return;


        waveInStop(hWaveIn);

        waveInReset(hWaveIn);


        for (
            int i = 0;
            i < headers.Length;
            i++
        )
        {

            waveInUnprepareHeader(
                hWaveIn,
                headers[i],
                Marshal.SizeOf<WAVEHDR>()
            );


            Marshal.FreeHGlobal(
                headers[i]
            );


            Marshal.FreeHGlobal(
                buffers[i]
            );
        }


        waveInClose(hWaveIn);

        hWaveIn = IntPtr.Zero;
    }
}

"@


# ------------------------------------------------------------
# CONECTAR AO SERVIDOR
# ------------------------------------------------------------

Write-Host ""
Write-Host "Conectando ao servidor..."
Write-Host "Servidor: $Servidor"
Write-Host "Porta: $Porta"

$tcp = New-Object System.Net.Sockets.TcpClient

$tcp.Connect(
    $Servidor,
    $Porta
)

$stream = $tcp.GetStream()

Write-Host "Conectado!"
Write-Host ""


# ------------------------------------------------------------
# CRIAR CAPTURA
# ------------------------------------------------------------

$microfone =
    New-Object MicrophoneCapture


# ------------------------------------------------------------
# ENVIAR ÁUDIO
# ------------------------------------------------------------

$microfone.Add_DataAvailable({

    param($audio)

    try
    {
        $stream.Write(
            $audio,
            0,
            $audio.Length
        )

        $stream.Flush()
    }
    catch
    {
        Write-Host "Erro ao enviar áudio:"
        Write-Host $_
    }

})


# ------------------------------------------------------------
# INICIAR MICROFONE
# ------------------------------------------------------------

Write-Host "Iniciando microfone..."
Write-Host ""

$microfone.Start(
    $SampleRate,
    $Channels,
    $Bits
)


Write-Host "=========================================="
Write-Host " MICROFONE TRANSMITINDO"
Write-Host "=========================================="
Write-Host ""
Write-Host "Formato: $SampleRate Hz / $Bits bits / Mono"
Write-Host "Destino: $Servidor`:$Porta"
Write-Host ""
Write-Host "Pressione ENTER para parar."
Write-Host ""


[void][Console]::ReadLine()


# ------------------------------------------------------------
# FINALIZAR
# ------------------------------------------------------------

Write-Host "Parando..."

$microfone.Stop()

$stream.Close()

$tcp.Close()

Write-Host "Transmissão encerrada."
