#dotnet new console -n MicStreamer
#cd MicStreamer
#dotnet publish -c Release -r win-x64 --self-contained false
#program.cs

using System;
using System.IO;
using System.Net.Sockets;
using System.Collections.Concurrent;
using System.Threading;
using System.Runtime.InteropServices;

namespace MicStreamer
{
    class Program
    {
        static void Main(string[] args)
        {
            // Ajuste aqui o IP e a Porta do seu servidor Whisper
            string servidor = "192.168.0.12";
            int porta = 5000;

            Console.WriteLine("==========================================");
            Console.WriteLine(" CLIENTE DE STREAM DE ÁUDIO -> WHISPER");
            Console.WriteLine("==========================================");
            Console.WriteLine($"Conectando a {servidor}:{porta}...");

            var streamer = new MicrophoneStreamer();

            // Captura o Ctrl+C para garantir que a placa de som e o socket fechem direito
            Console.CancelKeyPress += (sender, eventArgs) =>
            {
                Console.WriteLine("\nEncerrando transmissão...");
                streamer.Stop();
                eventArgs.Cancel = true;
            };

            try
            {
                // Parâmetros: Servidor, Porta, ID Dispositivo (0), Buffer (250ms)
                string status = streamer.Start(servidor, porta, 0, 250);
                
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"Conectado com sucesso!");
                Console.WriteLine($"Formato: {status}");
                Console.ResetColor();

                Console.WriteLine("\nTransmitindo áudio contínuo para o Whisper.");
                Console.WriteLine("Pressione [Ctrl+C] ou [Enter] para encerrar.\n");

                Console.ReadLine();
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"\n[ERRO]: {ex.Message}");
                Console.ResetColor();
            }
            finally
            {
                streamer.Stop();
                Console.WriteLine("Finalizado com sucesso.");
            }
        }
    }

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
        private WaveInProc callbackDelegate; // Mantém a referência viva contra o Garbage Collector

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
            // 1. Conexão TCP
            tcp = new TcpClient();
            tcp.Connect(host, port);
            netStream = tcp.GetStream();

            audioQueue = new BlockingCollection<byte[]>(new ConcurrentQueue<byte[]>());
            isRunning = true;

            // Thread dedicada para não travar o buffer de gravação
            sendThread = new Thread(SendWorker);
            sendThread.IsBackground = true;
            sendThread.Start();

            // 2. Negociação de formatos suportados pela placa
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
                    // 0x00000001 = WAVE_FORMAT_QUERY (teste sem abrir)
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

            if (!found) throw new Exception("Nenhum formato de áudio aceito pelo driver da placa de som.");

            // 3. Inicialização dos buffers da placa
            callbackDelegate = new WaveInProc(WaveCallback);

            uint res = waveInOpen(out handle, chosenDevice, chosenFormat, callbackDelegate, IntPtr.Zero, 0x00030000);
            if (res != 0) throw new Exception("Falha em waveInOpen. Código: " + res);

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
            if (res != 0) throw new Exception("Falha em waveInStart. Código: " + res);

            return $"{activeSampleRate} Hz / {activeChannels} canal(is) -> Convertendo para 16000 Hz Mono";
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
            catch { }
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
            catch { }
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

            if (netStream != null) { try { netStream.Close(); } catch { } netStream = null; }
            if (tcp != null) { try { tcp.Close(); } catch { } tcp = null; }
        }
    }
}
