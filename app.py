"""
Painel simples para o trabalho de procedures (banco Universidade).

Como rodar:
    .venv/bin/streamlit run app.py
"""
import os
import re
from pathlib import Path

import pandas as pd
import pymssql
import streamlit as st

PASTA = Path(__file__).parent

st.set_page_config(page_title="Universidade – Procedures", page_icon="🎓", layout="wide")


# ----------------------------------------------------------------------
# Conexão e helpers
# ----------------------------------------------------------------------
def conectar(database="Universidade"):
    cfg = st.session_state["cfg"]
    return pymssql.connect(
        server=cfg["server"],
        port=cfg["port"],
        user=cfg["user"],
        password=cfg["password"],
        database=database,
        autocommit=True,
        charset="UTF-8",
    )


def mensagem_erro(e):
    """Separa o código e a mensagem do THROW do texto extra do pymssql."""
    args = e.args
    # Às vezes o pymssql embrulha (codigo, mensagem) dentro de outra tupla
    if len(args) == 1 and isinstance(args[0], tuple):
        args = args[0]
    if len(args) >= 2 and isinstance(args[0], int):
        texto = args[1].decode("utf-8", "ignore") if isinstance(args[1], bytes) else str(args[1])
        return args[0], texto.split("DB-Lib error")[0].strip()
    return None, str(e)


def consulta(sql, params=None):
    with conectar() as conn:
        cur = conn.cursor(as_dict=True)
        cur.execute(sql, params)
        return pd.DataFrame(cur.fetchall())


def executar(sql, params=None):
    """Executa um comando (EXEC) e consome todos os resultados.
    Retorna (ok, codigo_erro, mensagem, ultimo_resultado)."""
    try:
        with conectar() as conn:
            cur = conn.cursor(as_dict=True)
            cur.execute(sql, params)
            ultimo = None
            while True:
                try:
                    linhas = cur.fetchall()
                    if linhas:
                        ultimo = pd.DataFrame(linhas)
                except pymssql.OperationalError:
                    pass  # comando sem resultado
                if not cur.nextset():
                    break
            return True, None, "OK", ultimo
    except pymssql.Error as e:
        codigo, msg = mensagem_erro(e)
        return False, codigo, msg, None


def rodar_arquivo_sql(nome):
    """Roda um arquivo .sql separando os lotes pelo GO."""
    texto = (PASTA / nome).read_text(encoding="utf-8")
    lotes = [l for l in re.split(r"(?im)^\s*GO\s*$", texto) if l.strip()]
    with conectar(database="master") as conn:
        cur = conn.cursor()
        for lote in lotes:
            cur.execute(lote)
            while cur.nextset():
                pass
    return len(lotes)


def ano_letivo():
    return int(consulta("SELECT YEAR(GETDATE()) AS ANO")["ANO"][0])


def cor_resultado(valor):
    cores = {
        "APROVADO": "#1e8e3e",
        "APROVADO EM EXAME": "#1e8e3e",
        "EXAME": "#e37400",
        "REPROVADO": "#d93025",
        "REPROVADO EM EXAME": "#d93025",
        "REPROVADO POR FALTA": "#d93025",
    }
    c = cores.get(valor)
    return f"color: {c}; font-weight: 600" if c else ""


def mostrar_matricula(df):
    if df is None or df.empty:
        st.info("Nenhuma linha.")
        return
    if "RESULTADO" in df.columns:
        st.dataframe(df.style.map(cor_resultado, subset=["RESULTADO"]), width="stretch", hide_index=True)
    else:
        st.dataframe(df, width="stretch", hide_index=True)


SQL_MATRICULA_COMPLETA = """
SELECT M.MATRICULA, A.NOME AS ALUNO, M.CURSO, M.MATERIA, MT.NOME AS NOME_MATERIA,
       MT.CARGAHORARIA, P.NOME AS PROFESSOR, M.PERLETIVO,
       M.N1, M.N2, M.N3, M.N4, M.MEDIA,
       M.F1, M.F2, M.F3, M.F4, M.TOTALFALTAS, M.PERCFREQ,
       M.NOTAEXAME, M.MEDIAFINAL, M.RESULTADO
FROM MATRICULA M
JOIN ALUNOS A ON A.MATRICULA = M.MATRICULA
JOIN MATERIAS MT ON MT.SIGLA = M.MATERIA
LEFT JOIN PROFESSOR P ON P.PROFESSOR = M.PROFESSOR
"""


def mostrar_resultado(ok, codigo, msg, df):
    if ok:
        st.success("Executado com sucesso.")
    else:
        st.error(f"Erro {codigo}: {msg}" if codigo else f"Erro: {msg}")
    if df is not None:
        mostrar_matricula(df)


# ----------------------------------------------------------------------
# Barra lateral: conexão
# ----------------------------------------------------------------------
st.sidebar.header("Conexão")
if "cfg" not in st.session_state:
    st.session_state["cfg"] = {
        "server": "localhost",
        "port": 1433,
        "user": "sa",
        "password": os.environ.get("MSSQL_SA_PASSWORD", ""),
    }
cfg = st.session_state["cfg"]
cfg["server"] = st.sidebar.text_input("Servidor", cfg["server"])
cfg["port"] = st.sidebar.number_input("Porta", value=cfg["port"], step=1)
cfg["user"] = st.sidebar.text_input("Usuário", cfg["user"])
cfg["password"] = st.sidebar.text_input("Senha", cfg["password"], type="password")

try:
    with conectar(database="master") as _c:
        _cur = _c.cursor()
        _cur.execute("SELECT DB_ID('Universidade')")
        existe_banco = _cur.fetchone()[0] is not None
    st.sidebar.success("Conectado ao SQL Server")
except Exception as e:
    codigo, msg = mensagem_erro(e)
    if codigo == 18456:
        st.sidebar.error("Senha (ou usuário) incorreta. Digite e aperte Enter.")
    else:
        st.sidebar.error(f"Sem conexão. Confira se o contêiner está ligado (docker start sqlserver).\n\n{msg}")
    st.title("🎓 Universidade – Procedures")
    st.info("Preencha a senha do usuário sa na barra lateral para começar.")
    st.stop()

if not existe_banco:
    st.sidebar.warning("O banco Universidade ainda não existe.")

st.sidebar.divider()
st.sidebar.subheader("Rodar scripts")
for arquivo in ["01_criacao.sql", "02_populacao.sql", "03_procedures.sql"]:
    if st.sidebar.button(f"▶ {arquivo}", width="stretch"):
        try:
            n = rodar_arquivo_sql(arquivo)
            st.sidebar.success(f"{arquivo}: {n} lotes executados.")
        except pymssql.Error as e:
            codigo, msg = mensagem_erro(e)
            st.sidebar.error(f"{arquivo} – erro {codigo}: {msg}")
st.sidebar.caption("01 e 02 só rodam uma vez num banco novo. O 03 pode rodar sempre (CREATE OR ALTER).")

if not existe_banco:
    st.title("🎓 Universidade – Procedures")
    st.info("Rode o 01_criacao.sql, o 02_populacao.sql e o 03_procedures.sql pela barra lateral.")
    st.stop()


# ----------------------------------------------------------------------
# Abas
# ----------------------------------------------------------------------
st.title("🎓 Universidade – Procedures")
aba_tab, aba_mat, aba_notas, aba_exame, aba_testes = st.tabs(
    ["📋 Tabelas", "🧑‍🎓 Matricular aluno", "📝 Lançar notas", "🧪 Exame", "✅ Rodar testes"]
)

# ---------- Tabelas ----------
with aba_tab:
    col1, col2, col3, col4 = st.columns(4)
    resumo = consulta("""
        SELECT (SELECT COUNT(*) FROM ALUNOS) AS ALUNOS,
               (SELECT COUNT(*) FROM CURSOS) AS CURSOS,
               (SELECT COUNT(*) FROM MATERIAS) AS MATERIAS,
               (SELECT COUNT(*) FROM MATRICULA) AS MATRICULAS
    """).iloc[0]
    col1.metric("Alunos", int(resumo["ALUNOS"]))
    col2.metric("Cursos", int(resumo["CURSOS"]))
    col3.metric("Matérias", int(resumo["MATERIAS"]))
    col4.metric("Linhas em MATRICULA", int(resumo["MATRICULAS"]))

    tabela = st.radio(
        "Tabela", ["MATRICULA (completa)", "ALUNOS", "CURSOS", "PROFESSOR", "MATERIAS"], horizontal=True
    )
    if tabela == "MATRICULA (completa)":
        filtro = st.selectbox("Resultado", ["Todos", "Com resultado", "Sem resultado"])
        sql = SQL_MATRICULA_COMPLETA
        if filtro == "Com resultado":
            sql += " WHERE M.RESULTADO IS NOT NULL"
        elif filtro == "Sem resultado":
            sql += " WHERE M.RESULTADO IS NULL"
        mostrar_matricula(consulta(sql + " ORDER BY M.MATRICULA, M.MATERIA"))
    else:
        st.dataframe(consulta(f"SELECT * FROM {tabela}"), width="stretch", hide_index=True)

# ---------- Matricular ----------
with aba_mat:
    st.caption("Chama a procMATRICULAALUNO: cadastra o aluno e matricula em todas as matérias do curso.")
    cursos = consulta("SELECT CURSO, NOME FROM CURSOS ORDER BY CURSO")
    with st.form("form_matricula"):
        nome = st.text_input("Nome do aluno", max_chars=50)
        curso = st.selectbox("Curso", cursos["CURSO"], format_func=lambda c: f"{c} – {cursos.set_index('CURSO').loc[c, 'NOME']}")
        enviar = st.form_submit_button("Matricular")
    if enviar:
        if not nome.strip():
            st.warning("Informe o nome.")
        else:
            ok, codigo, msg, _ = executar("EXEC procMATRICULAALUNO %s, %s", (nome.strip(), curso))
            if ok:
                nova = int(consulta("SELECT MAX(MATRICULA) AS M FROM ALUNOS WHERE NOME = %s", (nome.strip(),))["M"][0])
                st.success(f"{nome} matriculado com o número {nova}.")
                mostrar_matricula(consulta(SQL_MATRICULA_COMPLETA + " WHERE M.MATRICULA = %s", (nova,)))
            else:
                mostrar_resultado(ok, codigo, msg, None)


def escolher_linha(chave):
    linhas = consulta("""
        SELECT M.MATRICULA, A.NOME, M.CURSO, M.MATERIA, M.PERLETIVO, M.RESULTADO
        FROM MATRICULA M JOIN ALUNOS A ON A.MATRICULA = M.MATRICULA
        ORDER BY M.MATRICULA, M.MATERIA
    """)
    if linhas.empty:
        st.info("Nenhuma matrícula ainda. Matricule um aluno primeiro.")
        return None
    rotulos = [
        f"{r.MATRICULA} – {r.NOME} | {r.CURSO}/{r.MATERIA} | {r.PERLETIVO}" + (f" | {r.RESULTADO}" if pd.notna(r.RESULTADO) else "")
        for r in linhas.itertuples()
    ]
    i = st.selectbox("Aluno / matéria", range(len(rotulos)), format_func=lambda k: rotulos[k], key=chave)
    return linhas.iloc[i]


# ---------- Notas ----------
with aba_notas:
    st.caption("Chama a sp_CadastraNotas. Os erros das validações (THROW) aparecem em vermelho.")
    linha = escolher_linha("sel_notas")
    if linha is not None:
        with st.form("form_notas"):
            c1, c2, c3 = st.columns(3)
            bimestre = c1.number_input("Bimestre", value=1, step=1)
            nota = c2.number_input("Nota", value=7.0, step=0.5)
            falta = c3.number_input("Faltas", value=0, step=1)
            enviar = st.form_submit_button("Lançar")
        if enviar:
            ok, codigo, msg, _ = executar(
                "EXEC sp_CadastraNotas %s, %s, %s, %s, %s, %s, %s",
                (int(linha.MATRICULA), linha.CURSO, linha.MATERIA, str(linha.PERLETIVO), float(nota), int(falta), int(bimestre)),
            )
            mostrar_resultado(ok, codigo, msg, None)
            mostrar_matricula(consulta(
                SQL_MATRICULA_COMPLETA + " WHERE M.MATRICULA = %s AND M.MATERIA = %s",
                (int(linha.MATRICULA), linha.MATERIA),
            ))

# ---------- Exame ----------
with aba_exame:
    st.caption("Chama a sp_CadastraExame. Só aceita aluno em EXAME (ou que já fez o exame, para corrigir).")
    linha = escolher_linha("sel_exame")
    if linha is not None:
        with st.form("form_exame"):
            nota_exame = st.number_input("Nota do exame", value=5.0, step=0.5)
            enviar = st.form_submit_button("Lançar exame")
        if enviar:
            ok, codigo, msg, _ = executar(
                "EXEC sp_CadastraExame %s, %s, %s, %s, %s",
                (int(linha.MATRICULA), linha.CURSO, linha.MATERIA, int(linha.PERLETIVO), float(nota_exame)),
            )
            mostrar_resultado(ok, codigo, msg, None)
            mostrar_matricula(consulta(
                SQL_MATRICULA_COMPLETA + " WHERE M.MATRICULA = %s AND M.MATERIA = %s",
                (int(linha.MATRICULA), linha.MATERIA),
            ))

# ---------- Testes ----------
with aba_testes:
    st.caption(
        "Roda os mesmos cenários do 04_testes.sql e compara com o valor esperado. "
        "Cada execução cadastra 3 alunos novos (ANA SOUZA, BRUNO LIMA e CAIO ROCHA)."
    )
    if st.button("▶ Rodar todos os testes", type="primary"):
        ano = ano_letivo()
        anoc = str(ano)
        checks = []  # (teste, esperado, obtido, passou)

        def notas(mat, curso, materia, lista):
            for bim, (n, f) in enumerate(lista, start=1):
                ok, codigo, msg, _ = executar(
                    "EXEC sp_CadastraNotas %s, %s, %s, %s, %s, %s, %s", (mat, curso, materia, anoc, n, f, bim)
                )
                if not ok:
                    checks.append((f"Lançar {materia} bimestre {bim}", "sem erro", f"Erro {codigo}: {msg}", False))

        def linha_de(mat, materia):
            df = consulta(
                "SELECT MEDIA, PERCFREQ, NOTAEXAME, MEDIAFINAL, RESULTADO FROM MATRICULA "
                "WHERE MATRICULA = %s AND MATERIA = %s AND PERLETIVO = %s",
                (mat, materia, ano),
            )
            return df.iloc[0]

        def conferir(teste, esperado_res, esperado_media, esperado_freq, mat, materia):
            r = linha_de(mat, materia)
            obtido = f"{r.RESULTADO} | média final {r.MEDIAFINAL} | freq {r.PERCFREQ}%"
            esperado = f"{esperado_res} | média final {esperado_media} | freq {esperado_freq}%"
            passou = (
                r.RESULTADO == esperado_res
                and abs(float(r.MEDIAFINAL) - esperado_media) < 0.01
                and abs(float(r.PERCFREQ) - esperado_freq) < 0.01
            )
            checks.append((teste, esperado, obtido, passou))

        def espera_erro(teste, codigo_esperado, sql, params):
            ok, codigo, msg, _ = executar(sql, params)
            obtido = "sem erro" if ok else f"Erro {codigo}: {msg}"
            checks.append((teste, f"Erro {codigo_esperado}", obtido, (not ok) and codigo == codigo_esperado))

        with st.spinner("Rodando..."):
            # 1) Matrícula automática
            alunos = {}
            for nome, curso in [("ANA SOUZA", "ENG"), ("BRUNO LIMA", "ADM"), ("CAIO ROCHA", "SIS")]:
                executar("EXEC procMATRICULAALUNO %s, %s", (nome, curso))
                mat = int(consulta("SELECT MAX(MATRICULA) AS M FROM ALUNOS WHERE NOME = %s", (nome,))["M"][0])
                alunos[nome] = mat
                qtd_curso = int(consulta("SELECT COUNT(*) AS Q FROM MATERIAS WHERE CURSO = %s", (curso,))["Q"][0])
                qtd_aluno = int(consulta("SELECT COUNT(*) AS Q FROM MATRICULA WHERE MATRICULA = %s", (mat,))["Q"][0])
                checks.append((f"Matrícula automática – {nome} ({curso})", f"{qtd_curso} matérias", f"{qtd_aluno} matérias", qtd_curso == qtd_aluno))
            ana, bruno, caio = alunos["ANA SOUZA"], alunos["BRUNO LIMA"], alunos["CAIO ROCHA"]

            # 2) Aprovado
            notas(ana, "ENG", "BDA", [(8, 2), (7, 2), (9, 2), (8, 2)])
            conferir("ANA – BDA: aprovado", "APROVADO", 8.0, 94.44, ana, "BDA")

            # 3) Exame -> reprovado em exame -> correção -> aprovado em exame
            notas(bruno, "ADM", "CON", [(5, 1), (5, 1), (5, 1), (5, 1)])
            conferir("BRUNO – CON: fica em exame", "EXAME", 5.0, 95.0, bruno, "CON")
            executar("EXEC sp_CadastraExame %s, %s, %s, %s, %s", (bruno, "ADM", "CON", ano, 4))
            conferir("BRUNO – CON: exame 4", "REPROVADO EM EXAME", 4.5, 95.0, bruno, "CON")
            executar("EXEC sp_CadastraExame %s, %s, %s, %s, %s", (bruno, "ADM", "CON", ano, 6))
            conferir("BRUNO – CON: exame corrigido para 6", "APROVADO EM EXAME", 5.5, 95.0, bruno, "CON")

            # 4) Reprovado por nota
            notas(caio, "SIS", "ALG", [(2, 0), (2, 0), (2, 0), (2, 0)])
            conferir("CAIO – ALG: reprovado por nota", "REPROVADO", 2.0, 100.0, caio, "ALG")

            # 5) Reprovado por falta
            notas(caio, "SIS", "RED", [(9, 6), (9, 6), (9, 6), (9, 6)])
            conferir("CAIO – RED: reprovado por falta", "REPROVADO POR FALTA", 9.0, 70.0, caio, "RED")

            # 6) Validações
            N = "EXEC sp_CadastraNotas %s, %s, %s, %s, %s, %s, %s"
            E = "EXEC sp_CadastraExame %s, %s, %s, %s, %s"
            espera_erro("Bimestre 5", 50001, N, (ana, "ENG", "PRG", anoc, 7, 0, 5))
            espera_erro("Nota 11", 50002, N, (ana, "ENG", "PRG", anoc, 11, 0, 1))
            espera_erro("2º bimestre sem o 1º", 50003, N, (caio, "SIS", "SBD", anoc, 7, 0, 2))
            espera_erro("Matrícula inexistente", 50003, N, (99999, "ENG", "BDA", anoc, 7, 0, 1))
            espera_erro("Exame para aluno aprovado", 50004, E, (ana, "ENG", "BDA", ano, 8))
            espera_erro("Nota do exame 12", 50002, E, (bruno, "ADM", "CON", ano, 12))

        res = pd.DataFrame(checks, columns=["Teste", "Esperado", "Obtido", "Passou"])
        passou = int(res["Passou"].sum())
        total = len(res)
        if passou == total:
            st.success(f"Todos os {total} testes passaram.")
        else:
            st.error(f"{total - passou} de {total} testes falharam.")
        res["Passou"] = res["Passou"].map({True: "✅", False: "❌"})
        st.dataframe(res, width="stretch", hide_index=True)

        st.subheader("Resumo dos alunos de teste")
        mostrar_matricula(consulta(
            SQL_MATRICULA_COMPLETA + " WHERE M.MATRICULA IN (%s, %s, %s) ORDER BY A.NOME, M.MATERIA",
            (ana, bruno, caio),
        ))
