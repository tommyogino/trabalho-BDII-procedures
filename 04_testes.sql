USE Universidade;
GO

-- ======================================================================
-- Testes das procedures
-- Rodar depois do 01_criacao.sql, 02_populacao.sql e 03_procedures.sql.
-- Cada vez que roda, cadastra 3 alunos novos (as matrículas são buscadas
-- pelo nome, então os testes funcionam mesmo rodando de novo).
--
-- Ordem dos parâmetros:
-- sp_CadastraNotas  MATRICULA, CURSO, MATERIA, PERLETIVO, NOTA, FALTA, BIMESTRE
-- sp_CadastraExame  MATRICULA, CURSO, MATERIA, PERLETIVO, NOTAEXAME
-- ======================================================================

DECLARE @ANO INT = YEAR(GETDATE());
DECLARE @ANOC CHAR(4) = CAST(@ANO AS CHAR(4));  -- a sp_CadastraNotas recebe o ano como CHAR(4)
DECLARE @ANA INT, @BRUNO INT, @CAIO INT;

-- ----------------------------------------------------------------------
-- 1) Matrícula automática: cada aluno é matriculado em todas as matérias do curso
-- ----------------------------------------------------------------------
EXEC procMATRICULAALUNO 'ANA SOUZA', 'ENG';
EXEC procMATRICULAALUNO 'BRUNO LIMA', 'ADM';
EXEC procMATRICULAALUNO 'CAIO ROCHA', 'SIS';

SELECT @ANA   = MAX(MATRICULA) FROM ALUNOS WHERE NOME = 'ANA SOUZA';
SELECT @BRUNO = MAX(MATRICULA) FROM ALUNOS WHERE NOME = 'BRUNO LIMA';
SELECT @CAIO  = MAX(MATRICULA) FROM ALUNOS WHERE NOME = 'CAIO ROCHA';

-- Esperado: ANA com 4 matérias de ENG, BRUNO com 3 de ADM, CAIO com 3 de SIS
SELECT MATRICULA, CURSO, MATERIA, PROFESSOR, PERLETIVO
FROM MATRICULA
WHERE MATRICULA IN (@ANA, @BRUNO, @CAIO)
ORDER BY MATRICULA, MATERIA;

-- ----------------------------------------------------------------------
-- 2) APROVADO - ANA em BDA (144h)
--    Notas 8, 7, 9, 8 -> média 8 | 8 faltas -> 94,44% de frequência
-- ----------------------------------------------------------------------
EXEC sp_CadastraNotas @ANA, 'ENG', 'BDA', @ANOC, 8, 2, 1;
EXEC sp_CadastraNotas @ANA, 'ENG', 'BDA', @ANOC, 7, 2, 2;
EXEC sp_CadastraNotas @ANA, 'ENG', 'BDA', @ANOC, 9, 2, 3;
EXEC sp_CadastraNotas @ANA, 'ENG', 'BDA', @ANOC, 8, 2, 4;

-- ----------------------------------------------------------------------
-- 3) EXAME - BRUNO em CON (80h)
--    Notas 5, 5, 5, 5 -> média 5 | 4 faltas -> 95% de frequência
-- ----------------------------------------------------------------------
EXEC sp_CadastraNotas @BRUNO, 'ADM', 'CON', @ANOC, 5, 1, 1;
EXEC sp_CadastraNotas @BRUNO, 'ADM', 'CON', @ANOC, 5, 1, 2;
EXEC sp_CadastraNotas @BRUNO, 'ADM', 'CON', @ANOC, 5, 1, 3;
EXEC sp_CadastraNotas @BRUNO, 'ADM', 'CON', @ANOC, 5, 1, 4;

-- 3a) Exame com nota 4 -> média final (5 + 4) / 2 = 4,5 -> REPROVADO EM EXAME
EXEC sp_CadastraExame @BRUNO, 'ADM', 'CON', @ANO, 4;

-- 3b) Correção da nota do exame para 6 e reprocessamento
--     -> média final (5 + 6) / 2 = 5,5 -> APROVADO EM EXAME
EXEC sp_CadastraExame @BRUNO, 'ADM', 'CON', @ANO, 6;

-- ----------------------------------------------------------------------
-- 4) REPROVADO por nota - CAIO em ALG (144h)
--    Notas 2, 2, 2, 2 -> média 2 | 0 faltas -> 100% de frequência
-- ----------------------------------------------------------------------
EXEC sp_CadastraNotas @CAIO, 'SIS', 'ALG', @ANOC, 2, 0, 1;
EXEC sp_CadastraNotas @CAIO, 'SIS', 'ALG', @ANOC, 2, 0, 2;
EXEC sp_CadastraNotas @CAIO, 'SIS', 'ALG', @ANOC, 2, 0, 3;
EXEC sp_CadastraNotas @CAIO, 'SIS', 'ALG', @ANOC, 2, 0, 4;

-- ----------------------------------------------------------------------
-- 5) REPROVADO POR FALTA - CAIO em RED (80h)
--    Notas 9, 9, 9, 9 -> média 9, mas 24 faltas -> 70% de frequência
--    (a falta vale antes da nota)
-- ----------------------------------------------------------------------
EXEC sp_CadastraNotas @CAIO, 'SIS', 'RED', @ANOC, 9, 6, 1;
EXEC sp_CadastraNotas @CAIO, 'SIS', 'RED', @ANOC, 9, 6, 2;
EXEC sp_CadastraNotas @CAIO, 'SIS', 'RED', @ANOC, 9, 6, 3;
EXEC sp_CadastraNotas @CAIO, 'SIS', 'RED', @ANOC, 9, 6, 4;

-- ----------------------------------------------------------------------
-- 6) Validações - cada teste deve cair no CATCH e mostrar o erro na aba Messages
-- ----------------------------------------------------------------------
-- 6a) Bimestre inválido -> erro 50001
BEGIN TRY
    EXEC sp_CadastraNotas @ANA, 'ENG', 'PRG', @ANOC, 7, 0, 5;
END TRY
BEGIN CATCH
    PRINT CONCAT('6a) Erro ', ERROR_NUMBER(), ': ', ERROR_MESSAGE());
END CATCH

-- 6b) Nota maior que 10 -> erro 50002
BEGIN TRY
    EXEC sp_CadastraNotas @ANA, 'ENG', 'PRG', @ANOC, 11, 0, 1;
END TRY
BEGIN CATCH
    PRINT CONCAT('6b) Erro ', ERROR_NUMBER(), ': ', ERROR_MESSAGE());
END CATCH

-- 6c) Lançar o 2º bimestre sem ter lançado o 1º -> erro 50003
BEGIN TRY
    EXEC sp_CadastraNotas @CAIO, 'SIS', 'SBD', @ANOC, 7, 0, 2;
END TRY
BEGIN CATCH
    PRINT CONCAT('6c) Erro ', ERROR_NUMBER(), ': ', ERROR_MESSAGE());
END CATCH

-- 6d) Matrícula que não existe -> erro 50003
BEGIN TRY
    EXEC sp_CadastraNotas 99999, 'ENG', 'BDA', @ANOC, 7, 0, 1;
END TRY
BEGIN CATCH
    PRINT CONCAT('6d) Erro ', ERROR_NUMBER(), ': ', ERROR_MESSAGE());
END CATCH

-- 6e) Exame para quem foi APROVADO direto -> erro 50004
BEGIN TRY
    EXEC sp_CadastraExame @ANA, 'ENG', 'BDA', @ANO, 8;
END TRY
BEGIN CATCH
    PRINT CONCAT('6e) Erro ', ERROR_NUMBER(), ': ', ERROR_MESSAGE());
END CATCH

-- 6f) Nota do exame maior que 10 -> erro 50002
BEGIN TRY
    EXEC sp_CadastraExame @BRUNO, 'ADM', 'CON', @ANO, 12;
END TRY
BEGIN CATCH
    PRINT CONCAT('6f) Erro ', ERROR_NUMBER(), ': ', ERROR_MESSAGE());
END CATCH

-- ----------------------------------------------------------------------
-- 7) Resumo final
-- Esperado:
--   ANA   BDA -> APROVADO
--   BRUNO CON -> APROVADO EM EXAME (exame 6, média final 5,5)
--   CAIO  ALG -> REPROVADO
--   CAIO  RED -> REPROVADO POR FALTA
-- As outras matérias ficam sem resultado (sem notas lançadas)
-- ----------------------------------------------------------------------
SELECT A.NOME, M.MATERIA, MT.NOME AS NOME_MATERIA, MT.CARGAHORARIA,
       M.N1, M.N2, M.N3, M.N4, M.MEDIA, M.TOTALFALTAS, M.PERCFREQ,
       M.NOTAEXAME, M.MEDIAFINAL, M.RESULTADO
FROM MATRICULA M
JOIN ALUNOS A ON A.MATRICULA = M.MATRICULA
JOIN MATERIAS MT ON MT.SIGLA = M.MATERIA
WHERE M.MATRICULA IN (@ANA, @BRUNO, @CAIO)
ORDER BY A.NOME, M.MATERIA;
GO
