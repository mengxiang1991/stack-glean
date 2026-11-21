import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export class CredentialStore {
  private alias(): Uint8Array { return new util.TextEncoder().encodeInto('stackglean.v2ex'); }
  async read(): Promise<string> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias());
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    let rows: asset.AssetMap[] = [];
    try { rows = await asset.query(query); }
    catch (error) { if ((error as BusinessError).code !== 24000002) { throw new Error('安全存储读取失败。'); } }
    if (rows.length === 0) { return ''; }
    return new util.TextDecoder().decodeWithStream(rows[0].get(asset.Tag.SECRET) as Uint8Array);
  }
  async save(token: string): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias());
    const values: asset.AssetMap = new Map();
    values.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(token));
    let existing: asset.AssetMap[] = [];
    try { existing = await asset.query(query); }
    catch (error) { if ((error as BusinessError).code !== 24000002) { throw new Error('安全存储读取失败。'); } }
    if (existing.length > 0) { await asset.update(query, values); return; }
    values.set(asset.Tag.ALIAS, this.alias());
    values.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    await asset.add(values);
  }
  async remove(): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias());
    try { await asset.remove(query); }
    catch (error) { if ((error as BusinessError).code !== 24000002) { throw new Error('安全存储删除失败。'); } }
  }
}
