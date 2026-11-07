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

export const SPENDING_NATURE_COLORS: string[] = ['survival', 'experience', 'growth', 'emergency', 'calm', 'creative', 'social', 'neutral'];

export class ValidatedSpendingNature {
  readonly command: SpendingNatureCommand;

  constructor(command: SpendingNatureCommand) {
    const name = command.name.trim();
    if (command.id.trim().length === 0 || name.length === 0 || name.length > 20 ||
      SPENDING_NATURE_COLORS.indexOf(command.colorKey) < 0) {
      throw new Error('INVALID_SPENDING_NATURE');
    }
    this.command = { id: command.id, name: name, colorKey: command.colorKey };
  }
}
