# -*- coding: utf-8 -*-
"""Ponte para o MCP do Aseprite, por stdio.

POR QUE ELA EXISTE. O servidor do Aseprite esta instalado e registrado em
`.claude.json`, mas servidores MCP conectam na ABERTURA da sessao — numa sessao
que ja estava aberta quando ele foi instalado, as ferramentas nao existem. Em
vez de esperar um reinicio, esta ponte abre o mesmo servidor, faz o aperto de
mao e despacha as chamadas.

O STDIN FICA ABERTO ATE A ULTIMA RESPOSTA. A primeira versao escrevia tudo de
uma vez e deixava o `subprocess.run` fechar o stdin — e o servidor, ao ver o
EOF, desligava no meio da fila: a primeira chamada respondia e as seguintes
voltavam como "SEM RESPOSTA". Nao era erro de argumento, era a ponte matando o
servidor. Agora ela escreve, LE ate ter todas as respostas, e so entao fecha.

USO:
    python tools/ase.py chamadas.json

O arquivo e uma LISTA de chamadas, cada uma {"tool": nome, "args": {...}}. Elas
correm em ordem, no MESMO processo — abrir o Aseprite custa caro e varias
chamadas seguidas so pagam esse custo uma vez.
"""
import json
import os
import queue
import subprocess
import sys
import threading

PY = r"C:\Users\joaoa_qxom2wq\.aseprite-mcp\venv\Scripts\python.exe"
ASEPRITE = r"C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe"
ESPERA = 240.0     # segundos sem NENHUMA resposta nova antes de desistir


def _leitor(saida, fila):
    for linha in iter(saida.readline, b""):
        fila.put(linha)
    fila.put(None)


def executar(chamadas, silencioso=False):
    env = dict(os.environ)
    env["ASEPRITE_PATH"] = ASEPRITE
    env["PYTHONIOENCODING"] = "utf-8"

    p = subprocess.Popen([PY, "-m", "aseprite_mcp"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, env=env, bufsize=0)
    fila = queue.Queue()
    t = threading.Thread(target=_leitor, args=(p.stdout, fila), daemon=True)
    t.start()

    def manda(msg):
        p.stdin.write((json.dumps(msg) + "\n").encode("utf-8"))
        p.stdin.flush()

    manda({"jsonrpc": "2.0", "id": 1, "method": "initialize",
           "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                      "clientInfo": {"name": "prismon", "version": "1"}}})
    manda({"jsonrpc": "2.0", "method": "notifications/initialized"})
    for i, c in enumerate(chamadas):
        manda({"jsonrpc": "2.0", "id": 100 + i, "method": "tools/call",
               "params": {"name": c["tool"], "arguments": c.get("args", {})}})

    respostas = {}
    faltam = set(range(len(chamadas)))
    while faltam:
        try:
            linha = fila.get(timeout=ESPERA)
        except queue.Empty:
            break
        if linha is None:
            break
        try:
            m = json.loads(linha.decode("utf-8", "replace").strip())
        except Exception:
            continue
        if isinstance(m, dict) and isinstance(m.get("id"), int) and m["id"] >= 100:
            i = m["id"] - 100
            respostas[i] = m
            faltam.discard(i)

    try:
        p.stdin.close()
    except Exception:
        pass
    try:
        p.wait(timeout=20)
    except Exception:
        p.kill()

    resultados = []
    for i, c in enumerate(chamadas):
        m = respostas.get(i)
        if m is None:
            r = "SEM RESPOSTA"
        elif "error" in m:
            r = "ERRO: " + json.dumps(m["error"], ensure_ascii=False)[:300]
        else:
            partes = m.get("result", {}).get("content", [])
            r = " ".join(str(x.get("text", "")) for x in partes if isinstance(x, dict))
            if m.get("result", {}).get("isError"):
                r = "ERRO: " + r
        resultados.append(r)
        if not silencioso:
            marca = "!!" if r.startswith("ERRO") or r == "SEM RESPOSTA" else "ok"
            print("  %s %-26s %s" % (marca, c["tool"], r[:150].replace("\n", " ")))
    return resultados


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    with open(sys.argv[1], encoding="utf-8") as f:
        chamadas = json.load(f)
    resultados = executar(chamadas)
    ruins = sum(1 for r in resultados if r.startswith("ERRO") or r == "SEM RESPOSTA")
    print("%d chamadas, %d com erro" % (len(resultados), ruins))
    return 1 if ruins else 0


if __name__ == "__main__":
    sys.exit(main())
