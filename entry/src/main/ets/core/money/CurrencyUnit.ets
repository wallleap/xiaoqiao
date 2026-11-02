/** Immutable currency definition; an id identifies a particular precision version. */
export class CurrencyUnit {
  readonly id: string;
  readonly code: string;
  readonly scale: number;

  constructor(id: string, code: string, scale: number) {
    if (id.trim().length === 0 || !/^[A-Z]{3}$/.test(code) ||
      !Number.isInteger(scale) || scale < 0 || scale > 4) {
      throw new Error('INVALID_CURRENCY');
    }
    this.id = id;
    this.code = code;
    this.scale = scale;
  }

  matches(other: CurrencyUnit): boolean {
    return this.id === other.id && this.code === other.code && this.scale === other.scale;
  }
}
