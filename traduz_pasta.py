import os
import sys
from pathlib import Path
from faster_whisper import WhisperModel

# --- Configurações ---------------------------------------------------------
MODELO = "medium"
COMPUTE_TYPE = "float16"   # GPUs mais antigas / pouca VRAM: "int8_float16"
IDIOMA = None              # None = detecção automática; ou "en", "pt", etc.
SRT_COM_EXTENSAO = True    # True: "a.mp4.srt" / "a.mp3.srt" (evita colisão entre arquivos
                           # de mesmo nome); False: "a.srt"
EXTENSOES_SUPORTADAS = {".mp4", ".mkv", ".avi", ".mov", ".flv", ".mp3", ".wav", ".m4a"}

# --- Se estiver atrás de proxy corporativo com certificado próprio, defina
# --- antes de rodar (em vez de desativar a verificação SSL):
# ---   set SSL_CERT_FILE=C:\caminho\certificado.pem
# ---   set REQUESTS_CA_BUNDLE=C:\caminho\certificado.pem

# --- Registra as DLLs da NVIDIA instaladas via pip no Windows ---
if sys.platform == "win32":
    import site
    for base in site.getsitepackages():
        for sub in ("cublas", "cudnn"):
            bin_dir = Path(base) / "nvidia" / sub / "bin"
            if bin_dir.exists():
                os.add_dll_directory(str(bin_dir))


def formatar_timestamp(segundos: float) -> str:
    """Converte segundos para o formato SRT (HH:MM:SS,mmm) sem estourar os milissegundos."""
    total_ms = int(round(segundos * 1000))
    horas, resto = divmod(total_ms, 3_600_000)
    minutos, resto = divmod(resto, 60_000)
    segs, ms = divmod(resto, 1000)
    return f"{horas:02d}:{minutos:02d}:{segs:02d},{ms:03d}"


def caminho_srt(arquivo: Path) -> Path:
    if SRT_COM_EXTENSAO:
        return arquivo.with_name(arquivo.name + ".srt")
    return arquivo.with_suffix(".srt")


def processar_pasta():
    pasta_atual = Path(".")

    arquivos_video = sorted(
        (f for f in pasta_atual.iterdir()
         if f.is_file() and f.suffix.lower() in EXTENSOES_SUPORTADAS),
        key=lambda f: f.name.lower(),
    )

    if not arquivos_video:
        print("Nenhum vídeo compatível encontrado na pasta.")
        return

    print(f"Carregando o modelo faster-whisper '{MODELO}' na GPU (CUDA)...")
    model = WhisperModel(MODELO, device="cuda", compute_type=COMPUTE_TYPE)

    print(f"Total de {len(arquivos_video)} arquivo(s) para processar na GPU.\n")

    for i, arquivo in enumerate(arquivos_video, start=1):
        arquivo_srt = caminho_srt(arquivo)
        arquivo_tmp = arquivo_srt.with_name(arquivo_srt.name + ".tmp")

        if arquivo_srt.exists():
            print(f"[{i}/{len(arquivos_video)}] Pulando '{arquivo.name}' (SRT já existe).")
            continue

        print(f"[{i}/{len(arquivos_video)}] Processando na GPU: {arquivo.name}...")

        try:
            segments, info = model.transcribe(
                str(arquivo),
                language=IDIOMA,
                beam_size=5,
                vad_filter=True,  # reduz alucinações em silêncio/música
            )

            if IDIOMA is None:
                print(f"    Idioma detectado: {info.language} "
                      f"(confiança {info.language_probability:.0%})")

            # Escreve em arquivo temporário; só vira .srt ao terminar com sucesso
            with open(arquivo_tmp, "w", encoding="utf-8") as f_out:
                for idx, segment in enumerate(segments, start=1):
                    f_out.write(
                        f"{idx}\n"
                        f"{formatar_timestamp(segment.start)} --> "
                        f"{formatar_timestamp(segment.end)}\n"
                        f"{segment.text.strip()}\n\n"
                    )

            arquivo_tmp.replace(arquivo_srt)
            print(f" -> Salvo: {arquivo_srt.name}\n")

        except BaseException:
            # Ctrl+C, falta de VRAM, erro de leitura etc.: remove o parcial
            if arquivo_tmp.exists():
                arquivo_tmp.unlink()
            raise

    print("Todos os vídeos foram concluídos!")


if __name__ == "__main__":
    processar_pasta()
