import { BOOK_PALETTES, BOOK_ICON_KEYS, BookPalette } from './BookCoverCatalog';

export interface BookAppearance { coverPalette: string; coverIcon: string; }

export interface LedgerBook {
  entryCount?: string;
  coverPalette?: string;
  coverIcon?: string;
  id: string;
  name: string;
  revision: number;
  archived: boolean;
}

export interface LedgerBookDraft {
  coverPalette?: string;
  coverIcon?: string;
  id: string;
  name: string;
}

export class ValidatedLedgerBook {
  readonly draft: LedgerBookDraft;

  constructor(draft: LedgerBookDraft) {
    const name = draft.name.trim();
    if (draft.id.trim().length === 0 || name.length === 0 || name.length > 40) {
      throw new Error('INVALID_LEDGER_BOOK');
    }
    const palette = draft.coverPalette || 'butter';
    const icon = draft.coverIcon || 'lucide_notebook_text1';
    if (!BOOK_PALETTES.some((item: BookPalette) => item.key === palette) || !BOOK_ICON_KEYS.includes(icon)) {
      throw new Error('INVALID_BOOK_APPEARANCE');
    }
    this.draft = { id: draft.id, name: name, coverPalette: palette, coverIcon: icon };
  }
}
