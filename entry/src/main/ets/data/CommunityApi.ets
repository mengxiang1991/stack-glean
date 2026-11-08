import { http } from '@kit.NetworkKit';
import { Topic, Reply, Detail, Site } from '../domain/Models';

interface VMember { username: string; }
interface VNode { title: string; }
interface VTopic {
  id: number; title: string; content: string; content_rendered: string;
  replies: number; member: VMember; node: VNode; url: string;
}
interface VReply { id: number; content: string; content_rendered: string; member: VMember; }
interface VEnvelope { success: boolean; result: VTopic; }
interface VReplies { success: boolean; result: VReply[]; }
interface VProfile { success: boolean; result: VMember; }
interface DTopic { id: number; title: string; posts_count: number; category_id: number; }
interface DList { topic_list: DTopicList; }
interface DTopicList { topics: DTopic[]; }
interface DPost { id: number; username: string; post_number: number; cooked: string; }
interface DStream { posts: DPost[]; stream: number[]; }
interface DDetail extends DTopic { post_stream: DStream; }
interface DPosts { post_stream: DStream; }

// Native plain text renderer: remote markup is never executed.
export function readable(html: string): string {
  return html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<br\s*\/?\s*>/gi, '\n').replace(/<\/(p|div|pre|blockquote|li|h[1-6])>/gi, '\n\n')
    .replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&').replace(/\n{3,}/g, '\n\n').trim();
}
function mapV(t: VTopic): Topic {
  const item = new Topic();
  item.id = String(t.id); item.title = t.title; item.author = t.member?.username ?? '';
  item.category = t.node?.title ?? 'V2EX'; item.replies = t.replies ?? 0;
  item.url = `https://www.v2ex.com/t/${item.id}`;
  item.body = readable(t.content_rendered || t.content || '');
  item.html = t.content_rendered || '';
  return item;
}
function mapD(t: DTopic): Topic {
  const item = new Topic(); item.site = 'linuxdo'; item.id = String(t.id);
  item.title = t.title; item.category = 'Linux.do'; item.replies = Math.max(0, t.posts_count - 1);
  item.url = `https://linux.do/t/topic/${item.id}`; return item;
}
function mapReply(p: DPost): Reply {
  const reply = new Reply(); reply.id = String(p.id); reply.author = p.username;
  reply.floor = p.post_number; reply.body = readable(p.cooked); reply.html = p.cooked || ''; return reply;
}
export class CommunityApi {
  // Deliberately memory-only: never write credentials to Preferences or logs.
  private token: string = '';
  username: string = '';
  epoch: number = 0;
  logout(): void { this.token = ''; this.username = ''; this.epoch++; }
  private async get(path: string, site: Site, authenticated: boolean = false): Promise<string> {
    const request = http.createHttp();
    const headers: Record<string, string> = { 'Accept': 'application/json' };
    if (authenticated && this.token) { headers['Authorization'] = `Bearer ${this.token}`; }
    try {
      const response = await request.request((site === 'v2ex' ? 'https://www.v2ex.com' : 'https://linux.do') + path,
        { method: http.RequestMethod.GET, header: headers, connectTimeout: 12000, readTimeout: 20000 });
      if (response.responseCode === 401) { throw new Error('登录凭据失效，请退出后重新登录。'); }
      if (response.responseCode === 403) { throw new Error('站点拒绝访问或当前权限不足，可使用原站阅读。'); }
      if (response.responseCode === 429) { throw new Error('站点请求限流，请稍后重试。'); }
      if (response.responseCode !== 200) { throw new Error(`请求失败（${response.responseCode}），请稍后重试。`); }
      const result = String(response.result);
      if (!result.trim().startsWith('{') && !result.trim().startsWith('[')) {
        throw new Error('站点返回了网页验证，原生接口暂不可用，请使用原站。');
      }
      return result;
    } finally { request.destroy(); }
  }
  async login(token: string): Promise<string> {
    if (!token.trim()) { throw new Error('请输入个人访问令牌。'); }
    const previous = this.token; this.token = token.trim();
    try {
      const data = JSON.parse(await this.get('/api/v2/member', 'v2ex', true)) as VProfile;
      if (!data.success || !data.result?.username) { throw new Error('无法验证个人访问令牌。'); }
      this.username = data.result.username; this.epoch++; return this.username;
    } catch (error) { this.token = previous; throw new Error((error as Error).message || '登录验证失败。'); }
  }
  async feed(site: Site, hot: boolean, page: number): Promise<Topic[]> {
    if (site === 'v2ex') {
      // Public v1 latest/hot endpoints are finite lists, not paginated feeds.
      if (page > 0) { return []; }
      const items = JSON.parse(await this.get(hot ? '/api/topics/hot.json' : '/api/topics/latest.json', site)) as VTopic[];
      if (!Array.isArray(items)) { throw new Error('V2EX 列表数据格式不符合预期。'); }
      return items.map((t: VTopic) => mapV(t));
    }
    const data = JSON.parse(await this.get(`/${hot ? 'top' : 'latest'}.json?page=${page}`, site)) as DList;
    if (!data.topic_list?.topics) { throw new Error('Linux.do 列表格式不符合预期。'); }
    return data.topic_list.topics.map((t: DTopic) => mapD(t));
  }
  async detail(topic: Topic): Promise<Detail> {
    const result = new Detail(); result.topic = topic;
    if (topic.site === 'v2ex') {
      if (this.token) {
        const data = JSON.parse(await this.get(`/api/v2/topics/${topic.id}`, topic.site, true)) as VEnvelope;
        if (!data.success) { throw new Error('主题读取失败，可能没有访问权限。'); }
        result.topic = mapV(data.result);
      } else {
        const data = JSON.parse(await this.get(`/api/topics/show.json?id=${topic.id}`, topic.site)) as VTopic[];
        if (data.length === 0) { throw new Error('主题不存在或游客无权查看。'); }
        result.topic = mapV(data[0]);
      }
      result.replies = await this.vReplies(topic.id, 1);
      result.nextPage = result.replies.length > 0 && result.replies.length < result.topic.replies ? 2 : 0;
    } else {
      const data = JSON.parse(await this.get(`/t/${topic.id}.json`, topic.site)) as DDetail;
      const posts = data.post_stream.posts;
      const first = posts.find((p: DPost) => p.post_number === 1);
      const updated = mapD(data); updated.body = first ? readable(first.cooked) : '正文暂未加载，可在原站查看。';
      updated.html = first?.cooked ?? '';
      updated.author = first?.username ?? ''; result.topic = updated;
      result.replies = posts.filter((p: DPost) => p.post_number !== 1).map((p: DPost) => mapReply(p));
      const loaded = posts.map((p: DPost) => p.id);
      result.remainingIds = data.post_stream.stream.filter((id: number) => !loaded.includes(id));
    }
    return result;
  }
  async vReplies(id: string, page: number): Promise<Reply[]> {
    let rows: VReply[] = [];
    if (this.token) {
      const data = JSON.parse(await this.get(`/api/v2/topics/${id}/replies?p=${page}`, 'v2ex', true)) as VReplies;
      if (!data.success) { throw new Error('回复读取失败。'); } rows = data.result;
    } else {
      rows = JSON.parse(await this.get(`/api/replies/show.json?topic_id=${id}&page=${page}`, 'v2ex')) as VReply[];
    }
    if (!Array.isArray(rows)) { throw new Error('回复格式不符合预期。'); }
    return rows.map((r: VReply, index: number) => {
      const reply = new Reply(); reply.id = String(r.id); reply.author = r.member?.username ?? '';
      reply.floor = (page - 1) * 100 + index + 1; reply.body = readable(r.content_rendered || r.content || ''); reply.html = r.content_rendered || ''; return reply;
    });
  }
  async dReplies(id: string, ids: number[]): Promise<Reply[]> {
    const query = ids.map((value: number) => `post_ids[]=${value}`).join('&');
    const data = JSON.parse(await this.get(`/t/${id}/posts.json?${query}`, 'linuxdo')) as DPosts;
    return data.post_stream.posts.map((p: DPost) => mapReply(p));
  }
}
