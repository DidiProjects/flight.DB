-- Rotina passa a ser sempre one-way (origem → destino, só janela de ida).
-- Ida+volta vira açúcar de criação no front (gera 2 rotinas one-way: IDA e VOLTA).
-- Pré-requisito: as rotinas em produção já devem estar sem volta.

ALTER TABLE routines
  DROP COLUMN IF EXISTS return_start,
  DROP COLUMN IF EXISTS return_end;
