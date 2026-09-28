import os
import sys
import ssl
from pathlib import Path
from faster_whisper import WhisperModel

# --- Bypass SSL (caso ainda precise para downloads do Hugging Face) ---
os.environ["CURL_CA_BUNDLE"] = ""
ssl._create_default_https_context = ssl._create_unverified_context

# --- Registra as DLLs da NVIDIA instaladas via pip no Windows ---
if sys.platform == "win32":
    import site
    packages_paths = site.getsitepackages()
    for base in packages_paths:
        cublas_bin = Path(base) / "nvidia" / "cublas" / "bin"
        cudnn_bin = Path(base) / "nvidia" / "cudnn" / "bin"
        if cublas_bin.exists():
            os.add_dll_directory(str(cublas_bin))
        if cudnn_bin.exists():
            os.add_dll_directory(str(cudnn_bin))

EXTENSOES_SUPORTADAS = {".mp4", ".mkv", ".avi", ".mov", ".flv", ".mp3", ".wav", ".m4a"}

def formatar_timestamp(segundos: float) -> str:
    """Converte segundos para o formato padrão SRT: HH:MM:SS,mmm"""
    horas = int(segundos // 3600)
    minutos = int((segundos % 3600) // 60)
    segs = int(segundos % 60)
    milisegundos = int(round((segundos - int(segundos)) * 1000))
    return f"{horas:02d}:{minutos:02d}:{segs:02d},{milisegundos:03d}"

def processar_pasta():
    print("Carregando o modelo faster-whisper na GPU (CUDA)...")
    
    # device="cuda" com compute_type="float16" (padrão ideal para GPUs NVIDIA modernas)
    # Se sua placa for mais antiga (ex: GTX 1650/1060) ou tiver pouca VRAM, pode usar compute_type="int8_float16"
    model = WhisperModel("medium", device="cuda", compute_type="float16")
    
    pasta_atual = Path(".")
    
    arquivos_video = [
        f for f in pasta_atual.iterdir() 
        if f.is_file() and f.suffix.lower() in EXTENSOES_SUPORTADAS
    ]
    
    if not arquivos_video:
        print("Nenhum vídeo compatível encontrado na pasta.")
        return

    print(f"Total de {len(arquivos_video)} arquivo(s) para processar na GPU.\n")

    for i, arquivo in enumerate(arquivos_video, start=1):
        arquivo_srt = arquivo.with_suffix(".srt")
        
        if arquivo_srt.exists():
            print(f"[{i}/{len(arquivos_video)}] Pulando '{arquivo.name}' (SRT já existe).")
            continue

        print(f"[{i}/{len(arquivos_video)}] Processando na GPU: {arquivo.name}...")
        
        # beam_size=5 é o padrão de alta precisão
        segments, _ = model.transcribe(str(arquivo), language="en", beam_size=5)
        
        with open(arquivo_srt, "w", encoding="utf-8") as f_out:
            for idx, segment in enumerate(segments, start=1):
                inicio = formatar_timestamp(segment.start)
                fim = formatar_timestamp(segment.end)
                texto = segment.text.strip()
                
                f_out.write(f"{idx}\n")
                f_out.write(f"{inicio} --> {fim}\n")
                f_out.write(f"{texto}\n\n")
        
        print(f" -> Salvo: {arquivo_srt.name}\n")

    print("Todos os vídeos foram concluídos!")

if __name__ == "__main__":
    processar_pasta()
