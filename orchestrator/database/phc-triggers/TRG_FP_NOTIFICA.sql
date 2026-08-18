USE [wallup]
GO
/****** Object:  Trigger [dbo].[TRG_FP_NOTIFICA]    Script Date: 18/08/2026 14:25:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER TRIGGER [dbo].[TRG_FP_NOTIFICA]
ON [dbo].[fp]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @fpstamp VARCHAR(25), @operacao VARCHAR(10);

    SELECT @fpstamp = fpstamp FROM inserted;

    SET @operacao = CASE
        WHEN EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
        ELSE 'INSERT'
    END;

    -- só notifica documentos "K" (fpstamp a começar por K)
    IF @fpstamp NOT LIKE 'K%'
        RETURN;

    -- só notifica quando datai/dataf estão preenchidas
    -- ('19000101' é a data "vazia" do PHC para um campo de data sem valor)
    IF EXISTS (
        SELECT 1 FROM inserted i
        WHERE i.fpstamp = @fpstamp
          AND (i.datai = '19000101' OR i.dataf = '19000101')
    )
        RETURN;

    -- num UPDATE só notifica se datai ou dataf tiverem realmente mudado
    IF @operacao = 'UPDATE' AND NOT EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.fpstamp = i.fpstamp
        WHERE i.fpstamp = @fpstamp
          AND (i.datai <> d.datai OR i.dataf <> d.dataf)
    )
        RETURN;

    EXEC K_NOTIFICA_APROVADOR
        @oritable = 'FP',
        @oristamp = @fpstamp,
        @operacao = @operacao;
END;
