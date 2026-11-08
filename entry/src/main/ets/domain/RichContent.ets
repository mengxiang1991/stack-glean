// Rebuild markup from an allowlist; never retain remote styles, handlers or executable tags.
function attribute(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
function safeUrl(value: string, origin: string): string {
  let result = value.replace(/&amp;/g, '&').trim();
  if (result.startsWith('//')) { result = `https:${result}`; }
  else if (result.startsWith('/')) { result = origin + result; }
  if (!/^https:\/\/[a-z0-9.-]+(?::\d+)?(?:[/?#][^\s<>"'`\\]*)?$/i.test(result)) { return ''; }
  return attribute(result);
}
function readAttribute(tag: string, name: string): string {
  const pattern = new RegExp(`\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i');
  const match = tag.match(pattern);
  return match ? (match[1] ?? match[2] ?? match[3] ?? '') : '';
}
export function sanitizeContent(input: string, origin: string): string {
  const cleaned = input.replace(/<!--[^]*?-->/g, '')
    .replace(/<(script|style|iframe|object|svg|math|template)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '');
  const tokens = cleaned.split(/(<[^>]*>)/g);
  const allowed = ['p', 'div', 'br', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'strong', 'b', 'em', 'i', 's', 'del', 'u', 'blockquote', 'pre', 'code', 'ul', 'ol', 'li', 'table', 'thead', 'tbody', 'tr', 'th', 'td', 'a', 'img', 'details', 'summary', 'span', 'sup', 'sub'];
  return tokens.map((token: string) => {
    if (!token.startsWith('<')) { return token.replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
    const tag = token.match(/^<\s*(\/?)\s*([a-z0-9]+)\b/i);
    if (!tag) { return ''; }
    const name = tag[2].toLowerCase();
    if (!allowed.includes(name)) { return ''; }
    if (tag[1]) { return ['img', 'br', 'hr'].includes(name) ? '' : `</${name}>`; }
    if (name === 'a') {
      const href = safeUrl(readAttribute(token, 'href'), origin);
      return href ? `<a href="${href}" rel="noopener noreferrer">` : '<a>';
    }
    if (name === 'img') {
      const src = safeUrl(readAttribute(token, 'src'), origin);
      return src ? `<img src="${src}" alt="${attribute(readAttribute(token, 'alt'))}">` : '[图片地址不受支持]';
    }
    return `<${name}>`;
  }).join('');
}
// RichText uses physical CSS pixels; caller converts configured fp with UIContext.fp2px.
export function richDocument(html: string, fallback: string, size: number, dark: boolean, site: string): string {
  const origin = site === 'v2ex' ? 'https://www.v2ex.com' : 'https://linux.do';
  const content = html ? sanitizeContent(html, origin) : `<p>${attribute(fallback).replace(/\n/g, '<br>')}</p>`;
  return `<html><head><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><style>
    html,body{margin:0;padding:0;background:${dark ? '#14201d' : '#f4f5f2'};color:${dark ? '#e4eee7' : '#233d32'};font-family:sans-serif;font-size:${size}px;line-height:1.85;overflow-wrap:anywhere}
    p,div{margin:0 0 1em;font-size:inherit}span,li,td,th{font-size:inherit}img{max-width:100%;height:auto;border-radius:.5em}a{color:${dark ? '#8ed7b6' : '#287661'}}
    h1,h2,h3{line-height:1.5;font-size:1.25em}pre{overflow-x:auto;white-space:pre;padding:.75em;background:${dark ? '#263c32' : '#e6ece6'};border-radius:.5em}code{font-family:monospace;font-size:.95em}blockquote{margin:.75em 0;padding:.5em .85em;border-left:.18em solid #348869;background:${dark ? '#20332b' : '#e6ece6'}}
    table{display:block;max-width:100%;overflow-x:auto;border-collapse:collapse}td,th{border:1px solid #81978b;padding:6px}ul,ol{padding-left:24px}
    </style></head><body>${content}</body></html>`;
}
