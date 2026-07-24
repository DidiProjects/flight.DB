-- 002 — routines.priority: default 'brl' → 'cash'
--
-- O rename de terminologia brl→cash atualizou o CHECK (cash/pts/hyb) mas deixou
-- o DEFAULT antigo 'brl' em bancos já existentes. O default passou a violar o
-- próprio CHECK da coluna:
--
--   INSERT INTO routines (...sem priority...)
--   ERROR: new row violates check constraint "routines_priority_check"
--
-- Ou seja: nenhuma rotina pode ser criada sem informar priority explicitamente.
--
-- Idempotente (ALTER ... SET DEFAULT é absoluto, não incremental).

ALTER TABLE routines ALTER COLUMN priority SET DEFAULT 'cash';

-- Se alguma linha antiga ficou com o valor literal 'brl' gravado antes do CHECK
-- existir, normaliza. (Com o CHECK ativo isso é sempre 0 linhas.)
UPDATE routines SET priority = 'cash' WHERE priority = 'brl';
