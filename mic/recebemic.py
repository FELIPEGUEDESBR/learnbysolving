import socket
import threading
import queue
import numpy as np
from faster_whisper import WhisperModel

HOST = "0.0.0.0"
PORT = 443

SAMPLE_RATE = 16000
CHANNELS = 1
SAMPLE_WIDTH = 2
BYTES_PER_SEC = SAMPLE_RATE * SAMPLE_WIDTH  # 32.000 bytes/segundo

# Janela mínima para processar (ex: 2.5s) e máxima (ex: 7s)
MIN_CHUNK_BYTES = int(BYTES_PER_SEC * 2.5)

print("Carregando modelo Faster-Whisper...")
# Troque por device="cpu", compute_type="int8" caso não use GPU NVIDIA
model = WhisperModel("small", device="cuda", compute_type="float16")
print("Modelo carregado com sucesso!\n")


def worker_transcricao(audio_queue: queue.Queue, stop_event: threading.Event):
    """Worker dedicado para inferência sem travar a recepção de rede."""
    accumulated_bytes = bytearray()

    while not stop_event.is_set() or not audio_queue.empty():
        try:
            # Espera até 0.5s por novos dados
            data = audio_queue.get(timeout=0.5)
            accumulated_bytes.extend(data)
            audio_queue.task_done()
        except queue.Empty:
            pass

        # Dispara quando acumula o tamanho mínimo ou quando o stream terminou e sobrou áudio
        if len(accumulated_bytes) >= MIN_CHUNK_BYTES or (stop_event.is_set() and len(accumulated_bytes) > 0):
            chunk_to_process = bytes(accumulated_bytes)
            accumulated_bytes.clear()

            # Conversão PCM 16-bit -> Float32
            audio = np.frombuffer(chunk_to_process, dtype=np.int16).astype(np.float32) / 32768.0

            # Detecção de silêncio simples (RMS) para evitar rodar GPU em áudio vazio
            rms = np.sqrt(np.mean(audio**2))
            if rms < 0.005:  # limiar de ruído de fundo
                continue

            segments, _ = model.transcribe(
                audio,
                language="pt",
                beam_size=1,
                vad_filter=True,
                vad_parameters=dict(
                    min_silence_duration_ms=400,
                    speech_pad_ms=200
                ),
                condition_on_previous_text=False
            )

            text_pieces = [s.text.strip() for s in segments if s.text.strip()]
            if text_pieces:
                print(f"[Whisper]: {' '.join(text_pieces)}", flush=True)


def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(1)

    print(f"Servidor ativo em {HOST}:{PORT}")

    try:
        while True:
            print("\nAguardando cliente Windows conectar...")
            conn, addr = server.accept()
            print(f"Cliente conectado: {addr}")

            audio_queue = queue.Queue()
            stop_event = threading.Event()

            # Inicia thread de processamento
            transcription_thread = threading.Thread(
                target=worker_transcricao,
                args=(audio_queue, stop_event),
                daemon=True
            )
            transcription_thread.start()

            try:
                while True:
                    data = conn.recv(4096)
                    if not data:
                        print("Cliente desconectou.")
                        break
                    audio_queue.put(data)
            except (ConnectionResetError, BrokenPipeError):
                print("Conexão interrompida bruscamente pelo cliente.")
            finally:
                conn.close()
                stop_event.set()
                transcription_thread.join()
                print("Sessão finalizada. Pronto para próxima conexão.")

    except KeyboardInterrupt:
        print("\nServidor encerrado pelo operador.")
    finally:
        server.close()


if __name__ == "__main__":
    main()
