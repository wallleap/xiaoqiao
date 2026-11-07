import { BusinessError } from '@kit.BasicServicesKit';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { DavConfig, normalizedDav } from './WebDavClient';

/** Endpoint and credentials are updated together in one device-local protected asset. */
export class DavCredentials {
  private readonly alias: Uint8Array;
  constructor(alias: string = 'xiaoqiao.webdav.v1') { this.alias = new util.TextEncoder().encodeInto(alias); }
  async save(config: DavConfig): Promise<void> {
    const value = normalizedDav(config);
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, this.alias);
    attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(JSON.stringify(value)));
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(attributes);
  }
  async load(): Promise<DavConfig | undefined> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias); query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows = await asset.query(query);
      if (rows.length === 0) { return undefined; }
      const bytes = rows[0].get(asset.Tag.SECRET) as Uint8Array;
      return normalizedDav(JSON.parse(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes)) as DavConfig);
    } catch (error) {
      if ((error as BusinessError).code === asset.ErrorCode.NOT_FOUND) { return undefined; }
      throw new Error('DAV_CREDENTIALS');
    }
  }
  async remove(): Promise<void> {
    const query: asset.AssetMap = new Map(); query.set(asset.Tag.ALIAS, this.alias);
    await asset.remove(query);
  }
}
