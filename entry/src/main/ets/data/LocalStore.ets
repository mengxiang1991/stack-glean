import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Library, Topic, Detail, topicKey } from '../domain/Models';

// Small bounded MVP store. Credentials and authenticated responses are never persisted.
export class LocalStore {
  private store?: preferences.Preferences;
  private writes: Promise<void> = Promise.resolve();
  async open(context: common.UIAbilityContext): Promise<Library> {
    this.store = await preferences.getPreferences(context, 'reader_v1');
    const raw = await this.store.get('library', '') as string;
    if (!raw) { return new Library(); }
    const library = JSON.parse(raw) as Library;
    library.autoFallback = library.autoFallback ?? false;
    library.sourceOrder = library.sourceOrder ?? [];
    library.hiddenSources = library.hiddenSources ?? [];
    library.sourceLimit = Number.isFinite(library.sourceLimit) ? Math.max(0, Math.min(8, Math.floor(library.sourceLimit))) : 8;
    return library;
  }
  save(library: Library): Promise<void> {
    const snapshot = JSON.stringify(library);
    this.writes = this.writes.catch(() => {}).then(async () => {
      await this.store?.put('library', snapshot); await this.store?.flush();
    });
    return this.writes;
  }
  async cache(detail: Detail): Promise<void> {
    // Only anonymous data is passed here. Keep a maximum of 20 topics.
    const key = `topic:${topicKey(detail.topic)}`;
    const ids = JSON.parse(await this.store?.get('cache_keys', '[]') as string) as string[];
    const next = [key, ...ids.filter((id: string) => id !== key)];
    for (const old of next.slice(20)) { await this.store?.delete(old); }
    await this.store?.put(key, JSON.stringify(detail));
    await this.store?.put('cache_keys', JSON.stringify(next.slice(0, 20))); await this.store?.flush();
  }
  async cached(topic: Topic): Promise<Detail | undefined> {
    const raw = await this.store?.get(`topic:${topicKey(topic)}`, '') as string;
    return raw ? JSON.parse(raw) as Detail : undefined;
  }
  async clearCache(): Promise<void> {
    const ids = JSON.parse(await this.store?.get('cache_keys', '[]') as string) as string[];
    for (const id of ids) { await this.store?.delete(id); }
    await this.store?.put('cache_keys', '[]'); await this.store?.flush();
  }
}
