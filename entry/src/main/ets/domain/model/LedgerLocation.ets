/** Coordinates returned by Map Kit, stored in millionths of a degree without coordinate-system conversion. */
export interface LedgerLocation {
  latitudeE6: number;
  longitudeE6: number;
}

/** undefined preserves an existing location; null explicitly clears it. */
export function validateLedgerLocation(location: LedgerLocation | null | undefined): LedgerLocation | null | undefined {
  if (location === undefined || location === null) { return location; }
  if (!Number.isInteger(location.latitudeE6) || !Number.isInteger(location.longitudeE6) ||
    location.latitudeE6 < -90000000 || location.latitudeE6 > 90000000 ||
    location.longitudeE6 < -180000000 || location.longitudeE6 > 180000000) {
    throw new Error('INVALID_LEDGER_LOCATION');
  }
  return { latitudeE6: location.latitudeE6, longitudeE6: location.longitudeE6 };
}

export function locationFromDegrees(latitude: number, longitude: number): LedgerLocation {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || latitude < -90 || latitude > 90 ||
    longitude < -180 || longitude > 180) { throw new Error('INVALID_LEDGER_LOCATION'); }
  return { latitudeE6: Math.round(latitude * 1000000), longitudeE6: Math.round(longitude * 1000000) };
}
