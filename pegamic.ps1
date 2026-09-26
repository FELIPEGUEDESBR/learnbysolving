# ==========================================
# STREAM DE MICROFONE -> WHISPER
# Windows PowerShell (Robusto / Network Threading em C#)
# ==========================================

$Servidor = "192.168.0.12"
$Porta = 5000

Write-Host "=========================================="
Write-Host " STREAM DE MICROFONE -> WHISPER"
Write-Host "=========================================="
Write-Host "Servidor: $Servidor"
Write-Host "Porta:    $Porta"
Write-Host ""

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Net.Sockets;
using System.Collections.Concurrent;
using System.Threading;
using System.Runtime.InteropServices;

public class MicrophoneStreamer
{
    [StructLayout(LayoutKind.Sequential)]
    public class WAVEFORMATEX
    {
        public ushort wFormatTag = 1; // PCM
        public ushort nChannels;
        public uint nSamplesPerSec;
        public uint nAvgBytesPerSec;
        public ushort nBlockAlign;
        public ushort wBitsPerSample = 16;
        public ushort cbSize = 0;
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

    private delegate void WaveInProc(IntPtr hWaveIn, uint uMsg, IntPtr dwInstance, IntPtr dwParam1, IntPtr dwParam2);

    [DllImport("winmm.dll")]
    private static extern uint waveInOpen(out IntPtr phwi, uint uDeviceID, WAVEFORMATEX pwfx, WaveInProc dwCallback, IntPtr dwInstance, uint fdwOpen);

    [DllImport("winmm.dll")]
    private static extern uint waveInPrepareHeader(IntPtr hWaveIn, IntPtr lpWaveInHdr, uint uSize);

    [DllImport("winmm.dll")]
    private static extern uint waveInAddBuffer(IntPtr hWaveIn, IntPtr lpWaveInHdr, uint uSize);

    [DllImport("winmm.dll")]
    private static extern uint waveInStart(IntPtr hWaveIn);

    [DllImport("winmm.dll")]
    private static extern uint waveInStop(IntPtr hWaveIn);

    [DllImport("winmm.dll")]
    private static extern uint waveInReset(IntPtr hWaveIn);

    [DllImport("winmm.dll")]
    private static extern uint waveInUnprepareHeader(IntPtr hWaveIn, IntPtr lpWaveInHdr, uint uSize);

    [DllImport("winmm.dll")]
    private static extern uint waveInClose(IntPtr hWaveIn);

    private IntPtr handle = IntPtr.Zero;
    private WaveInProc callbackDelegate; // Referência fixa mantida viva

    private const int NUM_BUFFERS = 3;
    private IntPtr[] bufferDataPtrs = new IntPtr[NUM_BUFFERS];
    private IntPtr[] headerPtrs = new IntPtr[NUM_BUFFERS];

    private int activeSampleRate = 0;
    private int activeChannels = 0;

    private TcpClient tcp;
    private NetworkStream netStream;
    private BlockingCollection<byte[]> audioQueue;
    private Thread sendThread;
    private volatile bool isRunning = false;

    public string Start(string host, int port, int preferredDeviceId, int bufferDurationMs)
    {
        // Conexão TCP direta em C#
        tcp = new TcpClient();
        tcp.Connect(host, port);
        netStream = tcp.GetStream();

        audioQueue = new BlockingCollection<byte[]>(new ConcurrentQueue<byte[]>());
        isRunning = true;

        sendThread = new Thread(SendWorker);
        sendThread.IsBackground = true;
        sendThread.Start();

        // Lista de formatos para negociação
        int[][] candidates = new int[][]
        {
            new int[] { 16000, 1 },
            new int[] { 48000, 1 },
            new int[] { 48000, 2 },
            new int[] { 44100, 1 },
            new int[] { 44100, 2 }
        };

        uint[] devices = new uint[] { (uint)preferredDeviceId, 0xFFFFFFFF };
        WAVEFORMATEX chosenFormat = null;
        uint chosenDevice = 0;
        bool found = false;

        foreach (uint dev in devices)
        {
            foreach (var cand in candidates)
            {
                WAVEFORMATEX fmt = new WAVEFORMATEX();
                fmt.nChannels = (ushort)cand[1];
                fmt.nSamplesPerSec = (uint)cand[0];
                fmt.nBlockAlign = (ushort)(cand[1] * 2);
                fmt.nAvgBytesPerSec = (uint)(cand[0] * fmt.nBlockAlign);

                IntPtr dummy;
                uint check = waveInOpen(out dummy, dev, fmt, null, IntPtr.Zero, 0x00000001);
                if (check == 0)
                {
                    chosenFormat = fmt;
                    chosenDevice = dev;
                    activeSampleRate = cand[0];
                    activeChannels = cand[1];
                    found = true;
                    break;
                }
            }
            if (found) break;
        }

        if (!found) throw new Exception("Nenhum formato de audio aceito pelo driver.");

        // Fixa o delegate para nunca ser coletado pelo GC
        callbackDelegate = new WaveInProc(WaveCallback);

        uint res = waveInOpen(out handle, chosenDevice, chosenFormat, callbackDelegate, IntPtr.Zero, 0x00030000);
        if (res != 0) throw new Exception("Falha em waveInOpen. Cod: " + res);

        int bufferSize = (int)(chosenFormat.nAvgBytesPerSec * bufferDurationMs / 1000);
        uint headerSize = (uint)Marshal.SizeOf(typeof(WAVEHDR));

        for (int i = 0; i < NUM_BUFFERS; i++)
        {
            bufferDataPtrs[i] = Marshal.AllocHGlobal(bufferSize);

            WAVEHDR header = new WAVEHDR();
            header.lpData = bufferDataPtrs[i];
            header.dwBufferLength = (uint)bufferSize;
            header.dwUser = (IntPtr)i;

            headerPtrs[i] = Marshal.AllocHGlobal((int)headerSize);
            Marshal.StructureToPtr(header, headerPtrs[i], false);

            waveInPrepareHeader(handle, headerPtrs[i], headerSize);
            waveInAddBuffer(handle, headerPtrs[i], headerSize);
        }

        res = waveInStart(handle);
        if (res != 0) throw new Exception("Falha em waveInStart. Cod: " + res);

        return string.Format("{0} Hz / {1} canal(is) -> 16000 Hz Mono", activeSampleRate, activeChannels);
    }

    private void SendWorker()
    {
        try
        {
            while (isRunning)
            {
                byte[] chunk;
                if (audioQueue.TryTake(out chunk, 200))
                {
                    if (chunk != null && netStream != null)
                    {
                        netStream.Write(chunk, 0, chunk.Length);
                    }
                }
            }
        }
        catch {}
    }

    private void WaveCallback(IntPtr hWaveIn, uint uMsg, IntPtr dwInstance, IntPtr dwParam1, IntPtr dwParam2)
    {
        if (uMsg != 0x3C0 || handle == IntPtr.Zero || !isRunning) return; // 0x3C0 = WIM_DATA

        try
        {
            WAVEHDR header = (WAVEHDR)Marshal.PtrToStructure(dwParam1, typeof(WAVEHDR));
            int bytes = (int)header.dwBytesRecorded;

            if (bytes > 0)
            {
                int totalShorts = bytes / 2;
                short[] inPcm = new short[totalShorts];
                Marshal.Copy(header.lpData, inPcm, 0, totalShorts);

                int totalFrames = totalShorts / activeChannels;
                double ratio = (double)activeSampleRate / 16000.0;
                int outSamples = (int)(totalFrames / ratio);

                byte[] outBytes = new byte[outSamples * 2];
                int outByteIdx = 0;

                for (int i = 0; i < outSamples; i++)
                {
                    int srcFrame = (int)(i * ratio);
                    if (srcFrame >= totalFrames) break;

                    short sampleValue;
                    if (activeChannels == 1)
                    {
                        sampleValue = inPcm[srcFrame];
                    }
                    else
                    {
                        int l = inPcm[srcFrame * 2];
                        int r = inPcm[srcFrame * 2 + 1];
                        sampleValue = (short)((l + r) / 2);
                    }

                    outBytes[outByteIdx++] = (byte)(sampleValue & 0xFF);
                    outBytes[outByteIdx++] = (byte)((sampleValue >> 8) & 0xFF);
                }

                if (outByteIdx > 0)
                {
                    if (outByteIdx < outBytes.Length)
                    {
                        byte[] trimmed = new byte[outByteIdx];
                        Array.Copy(outBytes, trimmed, outByteIdx);
                        audioQueue.Add(trimmed);
                    }
                    else
                    {
                        audioQueue.Add(outBytes);
                    }
                }
            }

            uint headerSize = (uint)Marshal.SizeOf(typeof(WAVEHDR));
            waveInAddBuffer(handle, dwParam1, headerSize);
        }
        catch {}
    }

    public void Stop()
    {
        isRunning = false;

        if (handle != IntPtr.Zero)
        {
            waveInStop(handle);
            waveInReset(handle);

            uint headerSize = (uint)Marshal.SizeOf(typeof(WAVEHDR));

            for (int i = 0; i < NUM_BUFFERS; i++)
            {
                if (headerPtrs[i] != IntPtr.Zero)
                {
                    waveInUnprepareHeader(handle, headerPtrs[i], headerSize);
                    Marshal.FreeHGlobal(headerPtrs[i]);
                    headerPtrs[i] = IntPtr.Zero;
                }

                if (bufferDataPtrs[i] != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(bufferDataPtrs[i]);
                    bufferDataPtrs[i] = IntPtr.Zero;
                }
            }

            waveInClose(handle);
            handle = IntPtr.Zero;
        }

        if (netStream != null) { try { netStream.Close(); } catch {} netStream = null; }
        if (tcp != null) { try { tcp.Close(); } catch {} tcp = null; }
    }
}
"@

# ------------------------------------------
# EXECUÇÃO
# ------------------------------------------

$streamer = New-Object MicrophoneStreamer

try
{
    # Endereço, Porta, ID do Dispositivo (0), Buffer (250ms)
    $formato = $streamer.Start($Servidor, $Porta, 0, 250)
    Write-Host "Captura e Transmissão ativas: $formato" -ForegroundColor Green
    Write-Host "Fale ao microfone. Pressione Ctrl+C para encerrar.`n"

    while ($true) {
        Start-Sleep -Milliseconds 200
    }
}
catch {
    Write-Host "ERRO:" -ForegroundColor Red
    Write-Host $_.Exception.Message
}
finally
{
    if ($null -ne $streamer) {
        $streamer.Stop()
    }
    Write-Host "Finalizado com sucesso."
}
