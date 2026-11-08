export class WebSource {
  id: string;
  name: string;
  category: string;
  description: string;
  url: string;
  constructor(id: string, name: string, category: string, description: string, url: string) {
    this.id = id; this.name = name; this.category = category; this.description = description; this.url = url;
  }
}
export const WEB_SOURCES: WebSource[] = [
  new WebSource('v2ex', 'V2EX', '开发者社区', '开发者讨论与分享，直接打开原站。', 'https://www.v2ex.com/'),
  new WebSource('linuxdo', 'Linux.do', '开发者社区', '技术交流社区，网页登录与阅读。', 'https://linux.do/'),
  new WebSource('juejin', '稀土掘金', '技术实践', '中文开发经验、前后端与移动端实践文章。', 'https://juejin.cn/'),
  new WebSource('segmentfault', 'SegmentFault 思否', '技术问答', '开发问题讨论与技术经验交流。', 'https://segmentfault.com/'),
  new WebSource('infoq', 'InfoQ 中文站', '架构资讯', '软件架构、工程实践与行业技术资讯。', 'https://www.infoq.cn/'),
  new WebSource('oschina', '开源中国', '开源发现', '开源项目、开发者动态与技术社区。', 'https://www.oschina.net/'),
  new WebSource('github', 'GitHub Trending', '开源发现', '发现近期热门开源仓库，适合寻找项目与工具。', 'https://github.com/trending'),
  new WebSource('hackernews', 'Hacker News', '英文社区', '英文技术讨论、工程文章与创业话题链接。', 'https://news.ycombinator.com/')
];
export function orderedSources(order: string[]): WebSource[] {
  const ids = [...order, ...WEB_SOURCES.map((source: WebSource) => source.id)];
  const result: WebSource[] = [];
  ids.forEach((id: string) => {
    const source = WEB_SOURCES.find((item: WebSource) => item.id === id);
    if (source && !result.some((item: WebSource) => item.id === id)) { result.push(source); }
  });
  return result;
}
export function visibleSources(order: string[], hidden: string[], limit: number): WebSource[] {
  return orderedSources(order).filter((source: WebSource) => !hidden.includes(source.id))
    .slice(0, Math.max(0, Math.min(WEB_SOURCES.length, Math.floor(limit))));
}
export function moveSource(order: string[], id: string, direction: number): string[] {
  const ids = orderedSources(order).map((source: WebSource) => source.id);
  const index = ids.indexOf(id); const target = index + direction;
  if (index < 0 || target < 0 || target >= ids.length) { return ids; }
  const other = ids[target]; ids[target] = id; ids[index] = other; return ids;
}
