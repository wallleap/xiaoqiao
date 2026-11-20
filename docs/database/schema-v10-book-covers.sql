-- V10 additive book appearance. Original icon_key and all ledger amounts remain unchanged.
ALTER TABLE books ADD COLUMN cover_palette TEXT NOT NULL DEFAULT 'butter'
 CHECK(cover_palette IN ('butter','apricot','coral','rose','lilac','iris','mist','lagoon','mint','sage','oat','graphite'));
ALTER TABLE books ADD COLUMN cover_icon TEXT NOT NULL DEFAULT 'lucide_notebook_text1'
 CHECK(length(cover_icon) BETWEEN 9 AND 100 AND cover_icon GLOB 'lucide_*' AND cover_icon NOT GLOB '*[^a-z0-9_]*');
