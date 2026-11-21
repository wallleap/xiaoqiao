import { currencyUnit } from '../../core/money/Currencies';
import { BOOK_PALETTES, BOOK_ICON_KEYS, BookPalette } from './BookCoverCatalog';

export interface BookAppearance { currencyId?: string; monthStartDay?: number; coverPalette: string; coverIcon: string; }

export interface LedgerBook {
  currencyId?: string; monthStartDay?: number; currencyLocked?: boolean;
  entryCount?: string;
  coverPalette?: string;
  coverIcon?: string;
  id: string;
  name: string;
  revision: number;
  archived: boolean;
}

export interface LedgerBookDraft {
  currencyId?: string; monthStartDay?: number;
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
    const currencyId = draft.currencyId || 'CNY'; const monthStartDay = draft.monthStartDay === undefined ? 1 : draft.monthStartDay;
    currencyUnit(currencyId);
    if (!Number.isInteger(monthStartDay) || monthStartDay < 1 || monthStartDay > 31) { throw new Error('INVALID_MONTH_START_DAY'); }
    this.draft = { currencyId: currencyId, monthStartDay: monthStartDay, id: draft.id, name: name, coverPalette: palette, coverIcon: icon };
  }
}
