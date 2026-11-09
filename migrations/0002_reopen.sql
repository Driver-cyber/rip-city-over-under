-- The commissioner can reopen picks after tip-off (say, when the family is
-- watching on DVR) and close them again before grading.
ALTER TABLE games ADD COLUMN reopened INTEGER NOT NULL DEFAULT 0;
