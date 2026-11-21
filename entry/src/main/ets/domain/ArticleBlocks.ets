import { sanitizeContent } from './RichContent';

export class ArticleBlock {
  id: string;
  html: string;
  constructor(id: string, html: string) { this.id = id; this.html = html; }
}
function blockId(content: string): string {
  let hash = 0;
  for (let index = 0; index < content.length; index++) { hash = ((hash << 5) - hash + content.charCodeAt(index)) | 0; }
  return String(hash);
}
export function articleBlocks(html: string, site: string): ArticleBlock[] {
  const safe = sanitizeContent(html, site === 'v2ex' ? 'https://www.v2ex.com' : 'https://linux.do');
  const tokens = safe.split(/(<[^>]*>)/g);
  const result: ArticleBlock[] = [];
  let depth = 0;
  let buffer = '';
  const occurrences: Map<string, number> = new Map();
  for (const token of tokens) {
    buffer += token;
    const tag = token.match(/^<(\/?)([a-z0-9]+)/i);
    if (tag && !['img', 'br', 'hr'].includes(tag[2].toLowerCase())) { depth = Math.max(0, depth + (tag[1] ? -1 : 1)); }
    if (depth === 0 && buffer.trim()) {
      const hash = blockId(buffer);
      const count = occurrences.get(hash) ?? 0;
      occurrences.set(hash, count + 1);
      result.push(new ArticleBlock(hash + ':' + count, buffer));
      buffer = '';
    }
  }
  if (buffer.trim()) { result.push(new ArticleBlock(blockId(buffer) + ':tail', buffer)); }
  return result;
}
