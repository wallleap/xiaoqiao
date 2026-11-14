export interface CategoryProfile {
  id: string;
  kind: string;
  parentId: string;
  name: string;
  iconKey: string;
  sortOrder: number;
  revision: number;
  archived: boolean;
}

export interface CategoryCommand {
  id: string;
  kind: string;
  parentId?: string;
  name: string;
  iconKey: string;
}

/** Complete active sibling order, with revisions captured before dragging. */
export interface CategoryOrderItem {
  id: string;
  revision: number;
}

export class ValidatedCategory {
  readonly command: CategoryCommand;

  constructor(command: CategoryCommand) {
    const name = command.name.trim();
    const parent = command.parentId?.trim() || '';
    if (command.id.trim().length === 0 || (command.kind !== 'expense' && command.kind !== 'income') ||
      name.length === 0 || name.length > 20 || command.iconKey.trim().length === 0 || parent === command.id) {
      throw new Error('INVALID_CATEGORY');
    }
    this.command = { id: command.id, kind: command.kind, parentId: parent.length > 0 ? parent : undefined,
      name: name, iconKey: command.iconKey };
  }
}
