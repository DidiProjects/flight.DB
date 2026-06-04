-- Migration 005: Replace notification_mode (VARCHAR) with notification_modes (TEXT[])
--               and rename end_of_period_time to scheduled_time.
-- Idempotent: safe to run multiple times.

-- a) Add new column notification_modes
ALTER TABLE routines ADD COLUMN IF NOT EXISTS notification_modes TEXT[];

-- b) Migrate data from old column to new array column (only if old column still exists)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'routines' AND column_name = 'notification_mode'
    ) THEN
        UPDATE routines
        SET notification_modes = CASE notification_mode
            WHEN 'alert_only'           THEN ARRAY['target']
            WHEN 'daily_best_and_alert' THEN ARRAY['target', 'scheduled']
            WHEN 'end_of_period'        THEN ARRAY['scheduled']
        END
        WHERE notification_modes IS NULL;
    END IF;
END
$$;

-- c) Add NOT NULL constraint after migration
ALTER TABLE routines ALTER COLUMN notification_modes SET NOT NULL;

-- d) Add CHECK constraint for valid values
ALTER TABLE routines ADD CONSTRAINT IF NOT EXISTS notification_modes_valid
    CHECK (notification_modes <@ ARRAY['target', 'scheduled']);

-- e) Add CHECK constraint: at least one item in the array
ALTER TABLE routines ADD CONSTRAINT IF NOT EXISTS notification_modes_not_empty
    CHECK (array_length(notification_modes, 1) >= 1);

-- f) Rename end_of_period_time to scheduled_time (idempotent via DO block)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'routines' AND column_name = 'end_of_period_time'
    ) THEN
        ALTER TABLE routines RENAME COLUMN end_of_period_time TO scheduled_time;
    END IF;
END
$$;

-- g) Add default '20:00' for scheduled_time
ALTER TABLE routines ALTER COLUMN scheduled_time SET DEFAULT '20:00';

-- h) Backfill scheduled_time for rows with 'scheduled' mode that have NULL time
UPDATE routines
SET scheduled_time = '20:00'
WHERE 'scheduled' = ANY(notification_modes) AND scheduled_time IS NULL;

-- i) Drop old at_least_one_target constraint and create new conditional one
ALTER TABLE routines DROP CONSTRAINT IF EXISTS at_least_one_target;

ALTER TABLE routines ADD CONSTRAINT IF NOT EXISTS at_least_one_target_if_target_mode
    CHECK (
        NOT ('target' = ANY(notification_modes))
        OR (target_cash IS NOT NULL OR target_pts IS NOT NULL OR
            target_hyb_pts IS NOT NULL OR target_hyb_cash IS NOT NULL)
    );

-- j) Drop the old notification_mode column
ALTER TABLE routines DROP COLUMN IF EXISTS notification_mode;
