#### Instalando o linux
~~~~~
wsl --install
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
wsl --set-default-version 2
sc.exe config LxssManager start=auto
sc.exe start LxssManager
wsl --update
wsl --install -d kali-linux

~~~~~
~~~~~~
sudo apt update
sudo apt install unpaper ocrmypdf tesseract-ocr tesseract-ocr-por tesseract-ocr-eng
~~~~~~
#### Configurando o bash
~~~~~
nano ~/.bashrc
bind "set completion-ignore-case on"
bind "TAB:menu-complete"
source ~/.bashrc
~~~~~

#### converter_pdf.py
python converter_pdf.py dominio.pdf saida.pdf
~~~~~
import ocrmypdf
import sys
import os

def converter_pdf_para_pesquisavel(arquivo_entrada, arquivo_saida):
    """
    Converte um PDF não selecionável (imagem) em PDF pesquisável e selecionável.
    """
    try:
        ocrmypdf.ocr(
            arquivo_entrada,
            arquivo_saida,
            language="por+eng",  # português e inglês
            optimize=3,
            deskew=True,         # Corrige páginas tortas
            force_ocr=True       # Garante OCR mesmo se já houver texto
        )
        print(f"[OK] PDF pesquisável salvo em: {arquivo_saida}")
    except Exception as e:
        print("[ERRO] na conversão:", e)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Uso: python converter_pdf.py entrada.pdf saida.pdf")
    else:
        entrada = sys.argv[1]
        saida = sys.argv[2]
        if not os.path.exists(entrada):
            print("Arquivo de entrada não encontrado!")
        else:
            converter_pdf_para_pesquisavel(entrada, saida)
~~~~~
