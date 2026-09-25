# ============================================================
# STREAM DE MICROFONE
# PowerShell + .NET + winmm.dll
# Sem NAudio / FFmpeg
# ============================================================

$Servidor = "192.168.0.12"
$Porta = 5000

$SampleRate = 16000
$Bits = 16
$Channels = 1


# ============================================================
# CAPTURA DO MICROFONE
# ============================================================

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class MicrophoneCapture
{
    private const int CALLBACK_FUNCTION = 0x00030000;
    private const int WIM_DATA = 0x3C0;
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

        // CORREÇÃO: cast explícito para ushort
        format.nChannels = (ushort)channels;

        format.nSamplesPerSec = (uint)sampleRate;

        // CORREÇÃO: cast explícito para ushort
        format.wBitsPerSample = (ushort)bits;

        format.nBlockAlign =
            (ushort)(channels * bits / 8);

        format.nAvgBytesPerSec =
            (uint)(sampleRate * format.nBlockAlign);

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
                "Erro ao abrir o microfone. Código: "
                + result
            );
        }


        int bufferCount = 4;

        int bufferSize =
            sampleRate *
            channels *
            bits / 8 / 2;


        headers = new IntPtr[bufferCount];

        buffers = new IntPtr[bufferCount];


        for (int i = 0; i < bufferCount; i++)
        {

            buffers[i] =
                Marshal.AllocHGlobal(bufferSize);


            WAVEHDR header =
                new WAVEHDR();

            header.lpData = buffers[i];

            header.dwBufferLength =
                (uint)bufferSize;


            headers[i] =
                Marshal.AllocHGlobal(
                    Marshal.SizeOf(typeof(WAVEHDR))
                );


            Marshal.StructureToPtr(
                header,
                headers[i],
                false
            );


            waveInPrepareHeader(
                hWaveIn,
                headers[i],
                Marshal.SizeOf(typeof(WAVEHDR))
            );


            waveInAddBuffer(
                hWaveIn,
                headers[i],
                Marshal.SizeOf(typeof(WAVEHDR))
            );
        }


        result = waveInStart(hWaveIn);

        if (result != 0)
        {
            throw new Exception(
                "Erro ao iniciar captura. Código: "
                + result
            );
        }
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
            (WAVEHDR)Marshal.PtrToStructure(
                param1,
                typeof(WAVEHDR)
            );


        if (header.dwBytesRecorded > 0)
        {

            byte[] audio =
                new byte[
                    (int)header.dwBytesRecorded
                ];


            Marshal.Copy(
                header.lpData,
                audio,
                0,
                (int)header.dwBytesRecorded
            );


            // Compatível com compiladores C# antigos
            Action<byte[]> handler = DataAvailable;

            if (handler != null)
            {
                handler(audio);
            }
        }


        waveInAddBuffer(
            hWaveIn,
            param1,
            Marshal.SizeOf(typeof(WAVEHDR))
        );
    }


    public void Stop()
    {

        if (hWaveIn == IntPtr.Zero)
            return;


        waveInStop(hWaveIn);

        waveInReset(hWaveIn);


        if (headers != null)
        {
            for (
                int i = 0;
                i < headers.Length;
                i++
            )
            {

                waveInUnprepareHeader(
                    hWaveIn,
                    headers[i],
                    Marshal.SizeOf(typeof(WAVEHDR))
                );


                Marshal.FreeHGlobal(
                    headers[i]
                );


                Marshal.FreeHGlobal(
                    buffers[i]
                );
            }
        }


        waveInClose(hWaveIn);

        hWaveIn = IntPtr.Zero;
    }
}

"@


# ============================================================
# VERIFICAR SE A CLASSE FOI COMPILADA
# ============================================================

if (-not ("MicrophoneCapture" -as [type]))
{
    Write-Host ""
    Write-Host "ERRO: não foi possível carregar MicrophoneCapture."
    Write-Host "A captura não pode continuar."
    exit 1
}


# ============================================================
# CONEXÃO TCP
# ============================================================

Write-Host ""
Write-Host "=========================================="
Write-Host " STREAM DE MICROFONE"
Write-Host "=========================================="
Write-Host ""

Write-Host "Servidor: $Servidor"
Write-Host "Porta:    $Porta"
Write-Host ""

Write-Host "Conectando..."

$tcp = New-Object System.Net.Sockets.TcpClient

try
{
    $tcp.Connect(
        $Servidor,
        $Porta
    )
}
catch
{
    Write-Host ""
    Write-Host "ERRO: não foi possível conectar ao servidor."
    Write-Host $_
    exit 1
}

$stream = $tcp.GetStream()

Write-Host "Conectado!"
Write-Host ""


# ============================================================
# CRIAR CAPTURA
# ============================================================

$microfone =
    New-Object MicrophoneCapture


# ============================================================
# ENVIAR ÁUDIO
# ============================================================

$microfone.Add_DataAvailable({

    param($audio)

    try
    {
        if ($stream -ne $null)
        {
            $stream.Write(
                $audio,
                0,
                $audio.Length
            )
        }
    }
    catch
    {
        Write-Host ""
        Write-Host "Erro enviando áudio:"
        Write-Host $_
    }

})


# ============================================================
# INICIAR MICROFONE
# ============================================================

Write-Host "Iniciando microfone..."

try
{
    $microfone.Start(
        $SampleRate,
        $Channels,
        $Bits
    )
}
catch
{
    Write-Host ""
    Write-Host "ERRO ao iniciar microfone:"
    Write-Host $_

    $stream.Close()
    $tcp.Close()

    exit 1
}


Write-Host ""
Write-Host "=========================================="
Write-Host " MICROFONE TRANSMITINDO"
Write-Host "=========================================="
Write-Host ""
Write-Host "Formato : $SampleRate Hz / $Bits bits / Mono"
Write-Host "Destino : $Servidor`:$Porta"
Write-Host ""
Write-Host "Pressione ENTER para parar."
Write-Host ""


# ============================================================
# AGUARDAR
# ============================================================

[void][Console]::ReadLine()


# ============================================================
# FINALIZAR
# ============================================================

Write-Host ""
Write-Host "Encerrando..."

try
{
    $microfone.Stop()
}
catch
{
}

try
{
    $stream.Close()
}
catch
{
}

try
{
    $tcp.Close()
}
catch
{
}

Write-Host "Transmissão encerrada."
