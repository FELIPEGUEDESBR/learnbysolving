# ==========================================
# STREAM DE MICROFONE -> WHISPER
# Windows PowerShell
# ==========================================

$Servidor = "192.168.0.12"
$Porta = 5000

Write-Host ""
Write-Host "=========================================="
Write-Host " STREAM DE MICROFONE"
Write-Host "=========================================="
Write-Host ""
Write-Host "Servidor: $Servidor"
Write-Host "Porta:    $Porta"
Write-Host ""

# ------------------------------------------
# CÓDIGO C# PARA CAPTURA
# ------------------------------------------

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class MicrophoneCapture
{
    [StructLayout(LayoutKind.Sequential)]
    public class WAVEFORMATEX
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

    private delegate void WaveInProc(
        IntPtr hWaveIn,
        uint uMsg,
        IntPtr dwInstance,
        IntPtr dwParam1,
        IntPtr dwParam2
    );

    [DllImport("winmm.dll")]
    private static extern uint waveInOpen(
        out IntPtr phwi,
        uint uDeviceID,
        WAVEFORMATEX pwfx,
        WaveInProc dwCallback,
        IntPtr dwInstance,
        uint fdwOpen
    );

    [DllImport("winmm.dll")]
    private static extern uint waveInPrepareHeader(
        IntPtr hWaveIn,
        ref WAVEHDR lpWaveInHdr,
        uint uSize
    );

    [DllImport("winmm.dll")]
    private static extern uint waveInAddBuffer(
        IntPtr hWaveIn,
        ref WAVEHDR lpWaveInHdr,
        uint uSize
    );

    [DllImport("winmm.dll")]
    private static extern uint waveInStart(
        IntPtr hWaveIn
    );

    [DllImport("winmm.dll")]
    private static extern uint waveInStop(
        IntPtr hWaveIn
    );

    [DllImport("winmm.dll")]
    private static extern uint waveInReset(
        IntPtr hWaveIn
    );

    [DllImport("winmm.dll")]
    private static extern uint waveInUnprepareHeader(
        IntPtr hWaveIn,
        ref WAVEHDR lpWaveInHdr,
        uint uSize
    );

    [DllImport("winmm.dll")]
    private static extern uint waveInClose(
        IntPtr hWaveIn
    );

    private IntPtr handle = IntPtr.Zero;
    private WaveInProc callback;

    private IntPtr bufferPtr;
    private WAVEHDR header;

    public Action<byte[]> DataAvailable;

    private int bufferSize;

    public void Start(
        int deviceId,
        int sampleRate,
        int channels,
        int bits,
        int milliseconds
    )
    {
        WAVEFORMATEX format = new WAVEFORMATEX();

        format.wFormatTag = 1; // PCM
        format.nChannels = (ushort)channels;
        format.nSamplesPerSec = (uint)sampleRate;
        format.wBitsPerSample = (ushort)bits;

        format.nBlockAlign =
            (ushort)(channels * bits / 8);

        format.nAvgBytesPerSec =
            (uint)(sampleRate * channels * bits / 8);

        format.cbSize = 0;

        callback = WaveCallback;

        uint result = waveInOpen(
            out handle,
            (uint)deviceId,
            format,
            callback,
            IntPtr.Zero,
            0x00030000 // CALLBACK_FUNCTION
        );

        if (result != 0)
        {
            throw new Exception(
                "Erro ao abrir microfone. Código: " + result
            );
        }

        bufferSize =
            sampleRate *
            channels *
            bits / 8 *
            milliseconds / 1000;

        bufferPtr = Marshal.AllocHGlobal(bufferSize);

        header = new WAVEHDR();

        header.lpData = bufferPtr;
        header.dwBufferLength = (uint)bufferSize;

        result = waveInPrepareHeader(
            handle,
            ref header,
            (uint)Marshal.SizeOf(typeof(WAVEHDR))
        );

        if (result != 0)
        {
            throw new Exception(
                "waveInPrepareHeader falhou. Código: " + result
            );
        }

        result = waveInAddBuffer(
            handle,
            ref header,
            (uint)Marshal.SizeOf(typeof(WAVEHDR))
        );

        if (result != 0)
        {
            throw new Exception(
                "waveInAddBuffer falhou. Código: " + result
            );
        }

        result = waveInStart(handle);

        if (result != 0)
        {
            throw new Exception(
                "waveInStart falhou. Código: " + result
            );
        }
    }

    private void WaveCallback(
        IntPtr hWaveIn,
        uint uMsg,
        IntPtr dwInstance,
        IntPtr dwParam1,
        IntPtr dwParam2
    )
    {
        // WIM_DATA
        if (uMsg != 0x3C0)
            return;

        int bytes = (int)header.dwBytesRecorded;

        if (bytes > 0)
        {
            byte[] audio = new byte[bytes];

            Marshal.Copy(
                header.lpData,
                audio,
                0,
                bytes
            );

            Action<byte[]> handler = DataAvailable;

            if (handler != null)
            {
                handler(audio);
            }
        }

        // Recoloca o buffer para continuar capturando
        waveInAddBuffer(
            handle,
            ref header,
            (uint)Marshal.SizeOf(typeof(WAVEHDR))
        );
    }

    public void Stop()
    {
        if (handle != IntPtr.Zero)
        {
            waveInStop(handle);
            waveInReset(handle);

            waveInUnprepareHeader(
                handle,
                ref header,
                (uint)Marshal.SizeOf(typeof(WAVEHDR))
            );

            waveInClose(handle);

            handle = IntPtr.Zero;
        }

        if (bufferPtr != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(bufferPtr);
            bufferPtr = IntPtr.Zero;
        }
    }
}
"@

# ------------------------------------------
# VERIFICAR TIPO
# ------------------------------------------

if (-not ("MicrophoneCapture" -as [type]))
{
    Write-Host "ERRO: classe MicrophoneCapture não foi criada."
    exit 1
}

# ------------------------------------------
# TESTAR REDE
# ------------------------------------------

Write-Host "Testando conexão..."
Write-Host ""

$teste = Test-NetConnection `
    -ComputerName $Servidor `
    -Port $Porta `
    -WarningAction SilentlyContinue

if (-not $teste.TcpTestSucceeded)
{
    Write-Host "ERRO: não foi possível conectar ao servidor."
    exit 1
}

# ------------------------------------------
# CONECTAR TCP
# ------------------------------------------

$tcp = New-Object System.Net.Sockets.TcpClient

try
{
    Write-Host "Conectando..."

    $tcp.Connect(
        $Servidor,
        $Porta
    )

    Write-Host "Conectado!"
}
catch
{
    Write-Host ""
    Write-Host "ERRO ao conectar:"
    Write-Host $_.Exception.Message

    exit 1
}

$stream = $tcp.GetStream()

# ------------------------------------------
# CRIAR MICROFONE
# ------------------------------------------

$microfone = New-Object MicrophoneCapture

$microfone.DataAvailable = {
    param($audio)

    try
    {
        $stream.Write(
            $audio,
            0,
            $audio.Length
        )
    }
    catch
    {
        Write-Host ""
        Write-Host "Conexão encerrada."
    }
}

# ------------------------------------------
# INICIAR CAPTURA
# ------------------------------------------

Write-Host ""
Write-Host "Iniciando microfone..."
Write-Host ""
Write-Host "Dispositivo: ID 0"
Write-Host "Formato:     48000 Hz / 16 bits / 2 canais"
Write-Host ""
Write-Host "Transmitindo áudio..."
Write-Host "Pressione Ctrl+C para parar."
Write-Host ""

try
{
    $microfone.Start(
        0,      # dispositivo
        48000,  # sample rate
        2,      # canais
        16,     # bits
        500     # buffer de 500 ms
    )
}
catch
{
    Write-Host ""
    Write-Host "ERRO ao iniciar microfone:"
    Write-Host $_.Exception.Message

    $tcp.Close()
    exit 1
}

# ------------------------------------------
# MANTER PROGRAMA EXECUTANDO
# ------------------------------------------

try
{
    while ($true)
    {
        Start-Sleep -Milliseconds 100
    }
}
finally
{
    $microfone.Stop()
    $stream.Close()
    $tcp.Close()
}
