export const TAG_COLORS: string[] = ['brand', 'income', 'warning', 'alert', 'neutral'];

export interface TagProfile {
  id: string;
  name: string;
  colorKey: string;
  sortOrder: number;
  revision: number;
}

export interface TagCommand {
  id: string;
  name: string;
  colorKey: string;
}

export class ValidatedTag {
  readonly command: TagCommand;

  constructor(command: TagCommand) {
    const name = command.name.trim();
    if (command.id.trim().length === 0 || name.length === 0 || name.length > 20 ||
      !TAG_COLORS.includes(command.colorKey)) {
      throw new Error('INVALID_TAG');
    }
    this.command = { id: command.id, name: name, colorKey: command.colorKey };
  }
}
