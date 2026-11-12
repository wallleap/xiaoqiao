import { LedgerLocation } from '../../domain/model/LedgerLocation';
import { relationalStore } from '@kit.ArkData';

/** Writes per-entry text inside the caller's transaction; never renames a shared merchant. */
export class RdbMerchantFields {
  static async apply(db: relationalStore.RdbStore, id: string,
    merchantName: string | undefined, addressText: string | undefined, location: LedgerLocation | null | undefined = undefined): Promise<void> {
    if (merchantName !== undefined) {
      const name = merchantName.trim();
      // Retain an imported merchant link only when its displayed name has not changed.
      await db.executeSql("UPDATE transactions SET merchant_id=CASE WHEN " +
        "COALESCE(merchant_name_snapshot,(SELECT name FROM merchants WHERE id=transactions.merchant_id),'')=? " +
        "THEN merchant_id ELSE NULL END,merchant_name_snapshot=? WHERE id=?", [name, name || null, id]);
    }
    if (location !== undefined) {
      await db.update({ latitude_e6: location === null ? null : location.latitudeE6,
        longitude_e6: location === null ? null : location.longitudeE6 },
        new relationalStore.RdbPredicates('transactions').equalTo('id', id));
    } else if (addressText !== undefined) {
      // Older callers that edit text must not leave a pin pointing to the old address.
      await db.executeSql("UPDATE transactions SET latitude_e6=NULL,longitude_e6=NULL WHERE id=? AND COALESCE(address_text,'')<>?",
        [id, addressText.trim()]);
    }
    if (addressText !== undefined) {
      await db.update({ address_text: addressText.trim() || null },
        new relationalStore.RdbPredicates('transactions').equalTo('id', id));
    }
  }
}
