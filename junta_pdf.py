# Script: Mescla PDFs de uma pasta no WSL/Kali Linux de forma interativa

import PyPDF2
import os

def listar_pdfs(pasta):
    """Retorna lista de PDFs na pasta"""
    arquivos = [f for f in os.listdir(pasta) if f.lower().endswith(".pdf")]
    arquivos.sort()
    return arquivos

def merge_pdfs(pdf_list, pasta, output_name):
    """Mescla PDFs na ordem especificada"""
    merger = PyPDF2.PdfMerger()
    for pdf in pdf_list:
        caminho = os.path.join(pasta, pdf)
        merger.append(caminho)
    merger.write(os.path.join(pasta, output_name))
    merger.close()
    print(f"\nPDF final criado com sucesso: {output_name}")

if __name__ == "__main__":
    print("=== Mesclador de PDFs WSL/Kali Linux ===")
    pasta = input("Digite o caminho da pasta com os PDFs (ex: /mnt/c/Users/fel1p/Documents/Taxonomia bloom):\n").strip()

    if not os.path.isdir(pasta):
        print("Pasta inválida. Saindo...")
        exit()

    arquivos = listar_pdfs(pasta)
    if not arquivos:
        print("Nenhum PDF encontrado na pasta.")
        exit()

    print("\nPDFs encontrados:")
    for i, pdf in enumerate(arquivos, 1):
        print(f"{i}: {pdf}")

    ordem_input = input("\nDigite os números na ordem que deseja mesclar, separados por vírgula (ex: 3,1,2):\n")
    try:
        indices = [int(x.strip()) - 1 for x in ordem_input.split(",")]
        pdfs_ordenados = [arquivos[i] for i in indices]
    except:
        print("Ordem inválida. Saindo...")
        exit()

    output = input("Digite o nome do PDF final (ex: resultado.pdf):\n").strip()
    if not output.lower().endswith(".pdf"):
        output += ".pdf"

    merge_pdfs(pdfs_ordenados, pasta, output)

