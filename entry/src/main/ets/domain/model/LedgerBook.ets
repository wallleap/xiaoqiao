export interface LedgerBook {
  id: string;
  name: string;
  revision: number;
  archived: boolean;
}

export interface LedgerBookDraft {
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
    this.draft = { id: draft.id, name: name };
  }
}
