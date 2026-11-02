 -- Garante que as procedures sejam criadas no banco Universidade
 USE Universidade;
 GO

CREATE OR ALTER PROCEDURE procMATRICULAALUNO
    (
    @NOME VARCHAR(50),
    @CURSO CHAR(3)
    )
    AS
        BEGIN
                -- Variáveis para guardar a matrícula gerada e o ano letivo
                DECLARE @NovaMatricula INT
                DECLARE @PeriodoLetivo INT

                -- Cadastra o aluno. O SCOPE_IDENTITY() devolve o número de matrícula
                -- que o IDENTITY acabou de gerar
                INSERT INTO ALUNOS (NOME)
                VALUES (@NOME)
                SET @NovaMatricula = SCOPE_IDENTITY()
                -- O ano letivo é o ano atual
                SET @PeriodoLetivo = YEAR(GETDATE())

                -- INSERT com SELECT: cria uma linha na MATRICULA para cada matéria
                -- do curso, já com o professor da matéria
                INSERT MATRICULA (MATRICULA, CURSO, MATERIA, PROFESSOR, PERLETIVO)
                SELECT @NovaMatricula AS Matricula, CURSO, SIGLA, PROFESSOR,@PeriodoLetivo AS Periodo
                FROM MATERIAS
                WHERE @CURSO = CURSO


        SELECT * FROM MATRICULA

        END
    GO


CREATE OR ALTER PROCEDURE sp_CadastraNotas
	(
		@MATRICULA INT,
		@CURSO CHAR(3),
		@MATERIA CHAR(3),
		@PERLETIVO CHAR(4),
		@NOTA FLOAT,
		@FALTA INT,
		@BIMESTRE INT
	)
	AS
BEGIN

        -- O bimestre só pode ser de 1 a 4
        IF @BIMESTRE NOT BETWEEN 1 AND 4 THROW 50001, 'VALOR DO BIMESTRE INVALIDO.', 1;

        -- A nota só pode ser de 0 a 10
        IF @NOTA NOT BETWEEN 0 AND 10 THROW 50002, 'NOTA INVALIDA.', 1;

		IF @BIMESTRE = 1
		    BEGIN

                -- Só lança se a matrícula existir (senão o UPDATE não faria nada e não avisaria)
                IF NOT EXISTS (
                    SELECT 1 FROM MATRICULA
                    WHERE MATRICULA = @MATRICULA
                    AND CURSO = @CURSO
                    AND MATERIA = @MATERIA
                    AND PERLETIVO = @PERLETIVO)
                    THROW 50003, 'MATRICULA NAO ENCONTRADA.', 1;

                UPDATE MATRICULA
                SET N1 = @NOTA,
                    F1 = @FALTA,
                    TOTALPONTOS = @NOTA,
                    TOTALFALTAS = @FALTA,
                    MEDIA = @NOTA
                WHERE MATRICULA = @MATRICULA
                    AND CURSO = @CURSO
                    AND MATERIA = @MATERIA
                    AND PERLETIVO = @PERLETIVO;
		    END

        ELSE

        IF @BIMESTRE = 2
            BEGIN

                -- O bimestre 1 precisa ter nota e falta, senão N1 + nota daria NULL
                -- e a média ficaria vazia
                IF NOT EXISTS (
                    SELECT 1 FROM MATRICULA
                    WHERE MATRICULA = @MATRICULA
                    AND CURSO = @CURSO
                    AND MATERIA = @MATERIA
                    AND PERLETIVO = @PERLETIVO
                    AND N1 IS NOT NULL
                    AND F1 IS NOT NULL)
                    THROW 50003, 'MATRICULA NAO ENCONTRADA OU BIMESTRE 1 SEM NOTA/FALTA.', 1;

                UPDATE MATRICULA
                SET N2 = @NOTA,
                    F2 = @FALTA,
                    TOTALPONTOS = @NOTA + N1,
                    TOTALFALTAS = @FALTA + F1,
                    MEDIA = (@NOTA + N1) / 2
                WHERE MATRICULA = @MATRICULA
                    AND CURSO = @CURSO
                    AND MATERIA = @MATERIA
                    AND PERLETIVO = @PERLETIVO;
            END

        ELSE

        IF @BIMESTRE = 3
            BEGIN

                -- Os bimestres 1 e 2 precisam ter nota e falta
                IF NOT EXISTS (
                    SELECT 1 FROM MATRICULA
                    WHERE MATRICULA = @MATRICULA
                    AND CURSO = @CURSO
                    AND MATERIA = @MATERIA
                    AND PERLETIVO = @PERLETIVO
                    AND N1 IS NOT NULL AND N2 IS NOT NULL
                    AND F1 IS NOT NULL AND F2 IS NOT NULL)
                    THROW 50003, 'MATRICULA NAO ENCONTRADA OU BIMESTRES 1 E 2 SEM NOTA/FALTA.', 1;

                UPDATE MATRICULA
                SET N3 = @NOTA,
                    F3 = @FALTA,
                    TOTALPONTOS = @NOTA + N1 + N2,
                    TOTALFALTAS = @FALTA + F1 + F2,
                    MEDIA = (@NOTA + N1 + N2) / 3
                WHERE MATRICULA = @MATRICULA
                    AND CURSO = @CURSO
                    AND MATERIA = @MATERIA
                    AND PERLETIVO = @PERLETIVO;
            END

        ELSE

        IF @BIMESTRE = 4
            BEGIN

                -- @FALTAS guarda o total de faltas lido da tabela
                DECLARE @RESULTADO VARCHAR(50),
                        @FREQUENCIA FLOAT,
                        @MEDIAFINAL FLOAT,
                        @CARGAHORA INT,
                        @FALTAS INT

                -- O ";" no final é obrigatório porque o próximo comando é um THROW
                SET @CARGAHORA = (
                    SELECT CARGAHORARIA FROM MATERIAS
                    WHERE       SIGLA = @MATERIA
                            AND CURSO = @CURSO);

                -- Os bimestres 1 a 3 precisam ter nota e falta.
                -- Fica antes do UPDATE para não gravar o N4 quando der erro.
                IF NOT EXISTS (
                    SELECT 1 FROM MATRICULA
                    WHERE MATRICULA = @MATRICULA
                    AND CURSO = @CURSO
                    AND MATERIA = @MATERIA
                    AND PERLETIVO = @PERLETIVO
                    AND N1 IS NOT NULL AND N2 IS NOT NULL AND N3 IS NOT NULL
                    AND F1 IS NOT NULL AND F2 IS NOT NULL AND F3 IS NOT NULL)
                    THROW 50003, 'MATRICULA NAO ENCONTRADA OU BIMESTRES 1 A 3 SEM NOTA/FALTA.', 1;

                UPDATE MATRICULA
                SET N4 = @NOTA,
                    F4 = @FALTA,
                    TOTALPONTOS = @NOTA + N1 + N2 + N3,
                    TOTALFALTAS = @FALTA + F1 + F2 + F3,
                    MEDIA = (@NOTA + N1 + N2 + N3) / 4
                WHERE MATRICULA = @MATRICULA
                    AND CURSO = @CURSO
                    AND MATERIA = @MATERIA
                    AND PERLETIVO = @PERLETIVO;

                -- ---------- Apuração do resultado ----------

                -- Lê a média (arredondada em 2 casas) e o total de faltas já atualizados
                SELECT @MEDIAFINAL = ROUND(MEDIA, 2), @FALTAS = TOTALFALTAS
                FROM MATRICULA
                WHERE MATRICULA = @MATRICULA
                AND CURSO = @CURSO
                AND MATERIA = @MATERIA
                AND PERLETIVO = @PERLETIVO;

                -- % de frequência. Uso 100.0 para não cair na divisão inteira,
                -- que cortaria as casas decimais
                SET @FREQUENCIA = (@CARGAHORA - @FALTAS) * 100.0 / @CARGAHORA;

                -- Regras do resultado:
                -- frequência abaixo de 75% -> reprovado por falta (vale antes da nota)
                -- média >= 7 -> aprovado | média >= 3 -> exame | abaixo de 3 -> reprovado
                IF @FREQUENCIA < 75 SET @RESULTADO = 'REPROVADO POR FALTA';
                ELSE IF @MEDIAFINAL >= 7 SET @RESULTADO = 'APROVADO';
                ELSE IF @MEDIAFINAL >= 3 SET @RESULTADO = 'EXAME';
                ELSE SET @RESULTADO = 'REPROVADO';

                -- Grava a frequência, a média final e o resultado
                UPDATE MATRICULA
                SET PERCFREQ = CAST(@FREQUENCIA AS DECIMAL (10,2)), MEDIAFINAL = @MEDIAFINAL, RESULTADO = @RESULTADO
                WHERE MATRICULA = @MATRICULA
                AND CURSO = @CURSO
                AND MATERIA = @MATERIA
                AND PERLETIVO = @PERLETIVO;


            END


		SELECT * FROM MATRICULA	WHERE MATRICULA = @MATRICULA
END
GO

-- ======================================================================
-- sp_CadastraExame
-- Lança a nota do exame e reprocessa o resultado do aluno que ficou em EXAME.
-- ======================================================================
CREATE OR ALTER PROCEDURE sp_CadastraExame
	(
		@MATRICULA INT,
		@CURSO CHAR(3),
		@MATERIA CHAR(3),
		@PERLETIVO INT,
		@NOTAEXAME FLOAT
	)
	AS
BEGIN

        -- A nota do exame precisa ser de 0 a 10 e não pode ser vazia
        IF @NOTAEXAME IS NULL OR @NOTAEXAME NOT BETWEEN 0 AND 10
            THROW 50002, 'NOTA DO EXAME INVALIDA.', 1;

        -- Só aceita quem ficou em EXAME, ou quem já fez o exame (para corrigir a nota e reprocessar)
        IF NOT EXISTS (
            SELECT 1 FROM MATRICULA
            WHERE MATRICULA = @MATRICULA
            AND CURSO = @CURSO
            AND MATERIA = @MATERIA
            AND PERLETIVO = @PERLETIVO
            AND (RESULTADO = 'EXAME' OR NOTAEXAME IS NOT NULL))
            THROW 50004, 'MATRICULA NAO ENCONTRADA OU ALUNO NAO ESTA EM EXAME.', 1;

        -- Regra: média final = (média dos 4 bimestres + exame) / 2; aprova com 5
        UPDATE MATRICULA
        SET NOTAEXAME = @NOTAEXAME,
            MEDIAFINAL = ROUND((MEDIA + @NOTAEXAME) / 2, 2),
            RESULTADO = CASE
                            WHEN (MEDIA + @NOTAEXAME) / 2 >= 5 THEN 'APROVADO EM EXAME'
                            ELSE 'REPROVADO EM EXAME'
                        END
        WHERE MATRICULA = @MATRICULA
            AND CURSO = @CURSO
            AND MATERIA = @MATERIA
            AND PERLETIVO = @PERLETIVO;

        -- Mostra só a linha da matéria do exame
        SELECT * FROM MATRICULA
        WHERE MATRICULA = @MATRICULA
            AND CURSO = @CURSO
            AND MATERIA = @MATERIA
            AND PERLETIVO = @PERLETIVO;
END
GO
