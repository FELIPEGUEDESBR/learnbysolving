import sys
from pdf2docx import Converter

def show_progress(current, total):
    percent = int(current / total * 100)
    print(f"\rConvertendo: {percent}% ({current}/{total})", end='')

def pdf_para_docx(pdf_path, docx_path):
    cv = Converter(pdf_path)
    cv.convert(docx_path, start=0, end=None, progress_bar=show_progress)
    cv.close()
    print()  # Para quebrar a linha após o progresso

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Uso: python conv_pdf_word.py arquivo.pdf arquivo.docx")
    else:
        pdf_para_docx(sys.argv[1], sys.argv[2])
        print(f"Arquivo {sys.argv[2]} gerado com sucesso.")