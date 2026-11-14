export interface SpendingNatureProfile {
  id: string;
  name: string;
  colorKey: string;
  builtIn: boolean;
  sortOrder: number;
  revision: number;
  archived: boolean;
}

export interface SpendingNatureCommand {
  id: string;
  name: string;
  colorKey: string;
}

export interface BudgetNatureLine {
  natureId: string;
  name: string;
  colorKey: string;
  amountMinor: string;
  usedMinor: string;
  archived: boolean;
}

export const SPENDING_NATURE_COLORS: string[] = ['survival', 'experience', 'growth', 'emergency', 'calm', 'creative', 'social', 'neutral'];

export function isCustomNatureColor(value: string): boolean { return /^#[0-9a-fA-F]{6}$/.test(value); }
export function isSpendingNatureColor(value: string): boolean {
  return SPENDING_NATURE_COLORS.includes(value) || isCustomNatureColor(value);
}

export class ValidatedSpendingNature {
  readonly command: SpendingNatureCommand;

  constructor(command: SpendingNatureCommand) {
    const name = command.name.trim();
    if (command.id.trim().length === 0 || name.length === 0 || name.length > 20 ||
      !isSpendingNatureColor(command.colorKey)) {
      throw new Error('INVALID_SPENDING_NATURE');
    }
    this.command = { id: command.id, name: name, colorKey: isCustomNatureColor(command.colorKey) ? command.colorKey.toUpperCase() : command.colorKey };
  }
}
