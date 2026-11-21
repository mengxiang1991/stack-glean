import { Topic, Library, topicKey } from './Models';

interface BookmarkBackup {
  version: number;
  bookmarks: Topic[];
}
export function exportBookmarks(library: Library): string {
  const backup: BookmarkBackup = { version: 1, bookmarks: library.bookmarks };
  return JSON.stringify(backup, null, 2);
}
export function importBookmarks(text: string, current: Topic[]): Topic[] {
  if (text.length > 2000000) { throw new Error('导入文件过大，最多支持 2 MB。'); }
  const backup = JSON.parse(text) as BookmarkBackup;
  if (backup.version !== 1 || !Array.isArray(backup.bookmarks) || backup.bookmarks.length > 200) {
    throw new Error('收藏文件格式或版本不受支持。');
  }
  const result = current.slice();
  for (const row of backup.bookmarks) {
    if (!row || typeof row.id !== 'string' || typeof row.title !== 'string' ||
      typeof row.url !== 'string' || !/^https:\/\/[^\s]+$/i.test(row.url) ||
      !['v2ex', 'linuxdo'].includes(row.site) || typeof row.webOnly !== 'boolean') {
      throw new Error('收藏文件中存在无效条目。');
    }
    const topic = new Topic();
    topic.id = row.id; topic.title = row.title.slice(0, 1000); topic.url = row.url;
    topic.site = row.site; topic.webOnly = row.webOnly;
    if (!topic.webOnly) {
      if (!/^\d+$/.test(topic.id)) { throw new Error('原生主题编号无效。'); }
      topic.url = topic.site === 'v2ex' ? 'https://www.v2ex.com/t/' + topic.id : 'https://linux.do/t/topic/' + topic.id;
    }
    topic.author = typeof row.author === 'string' ? row.author : '';
    topic.category = typeof row.category === 'string' ? row.category : '';
    topic.replies = Number.isFinite(row.replies) ? Math.max(0, row.replies) : 0;
    topic.read = row.read === true;
    topic.tags = Array.isArray(row.tags) ? row.tags.filter((tag: string) => typeof tag === 'string').slice(0, 10) : [];
    if (!result.some((item: Topic) => topicKey(item) === topicKey(topic))) { result.push(topic); }
  }
  if (result.length > 200) { throw new Error('合并后超过 200 条，请先清理收藏。'); }
  return result;
}
