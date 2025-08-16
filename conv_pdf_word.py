import sys
import os
from pdf2docx import Converter

def pdf_para_word(pdf_path, word_path):
    cv = Converter(pdf_path)
    cv.convert(word_path, start=0, end=None)
    cv.close()
    print(f'Conversão concluída: {word_path}')

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Uso: python conv_pdf_word.py <ficheiro.pdf> <ficheiro.docx>")
        sys.exit(1)
    pdf_path = sys.argv[1]
    word_path = sys.argv[2]
    if not os.path.isfile(pdf_path):
        print(f"Ficheiro não encontrado: {pdf_path}")
        sys.exit(1)
    pdf_para_word(pdf_path, word_path)