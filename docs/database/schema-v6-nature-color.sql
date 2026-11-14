-- V6: optional custom RGB color; existing preset tokens and rows remain unchanged.
ALTER TABLE spending_natures ADD COLUMN custom_color TEXT CHECK(custom_color IS NULL OR (length(custom_color)=7 AND substr(custom_color,1,1)='#' AND substr(custom_color,2) NOT GLOB '*[^0-9A-F]*'));
