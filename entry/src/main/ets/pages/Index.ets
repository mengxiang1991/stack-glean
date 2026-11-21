import { useSideNavigation, useSplitReader, readerPaneWidth } from '../domain/ResponsiveLayout';
import { articleBlocks, ArticleBlock } from '../domain/ArticleBlocks';
import { ReaderTools } from '../components/ReaderTools';
import { CredentialStore } from '../data/CredentialStore';
import { BookmarkFiles } from '../data/BookmarkFiles';
import { exportBookmarks, importBookmarks } from '../domain/BookmarkTransfer';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { Topic, Reply, Detail, Library, Site, topicKey, readingOffsetToSave } from '../domain/Models';
import { CommunityApi, ApiError } from '../data/CommunityApi';
import { LocalStore } from '../data/LocalStore';
import { richDocument } from '../domain/RichContent';
import { WEB_SOURCES, WebSource, orderedSources, visibleSources, moveSource } from '../domain/WebSources';

class FeedSnapshot {
  topics: Topic[] = [];
  offset: number = 0;
  page: number = 0;
  more: boolean = false;
}
@Entry
@Component
struct Index {
  @State private windowWidth: number = 400;
  @State private site: Site = 'v2ex';
  @State private tab: number = 0;
  @State private hot: boolean = false;
  @State private topics: Topic[] = [];
  @State private busy: boolean = false;
  @State private loadingMore: boolean = false;
  @State private error: string = '';
  @State private message: string = '';
  @State private selected?: Detail = undefined;
  @State private library: Library = new Library();
  @State private accountName: string = '';
  @State private tokenInput: string = '';
  @State private loginBusy: boolean = false;
  @State private webUrl: string = '';
  @State private fallbackNotice: string = '';
  @State private sourceFilter: string = '';
  @State private settingsPage: string = 'home';
  @State private ready: boolean = false;
  @State private detailLoaded: boolean = false;
  @State private detailFailed: boolean = false;
  @State private libraryQuery: string = '';
  @State private unreadOnly: boolean = false;
  @State private floorInput: string = '';
  @State private webTools: boolean = false;
  @State private webSearch: string = '';
  @State private webProgress: number = 0;
  @State private restoring: boolean = false;
  private credentials: CredentialStore = new CredentialStore();
  private bookmarkFiles: BookmarkFiles = new BookmarkFiles();
  private feedSnapshots: Map<string, FeedSnapshot> = new Map();
  private api: CommunityApi = new CommunityApi();
  private storage: LocalStore = new LocalStore();
  private webController: webview.WebviewController = new webview.WebviewController();
  private detailScroller: Scroller = new Scroller();
  private feedScroller: Scroller = new Scroller();
  private feedOffset: number = 0;
  private requestId: number = 0;
  private detailRequestId: number = 0;
  private feedPage: number = 0;
  @State private more: boolean = false;
  private progressY: number | undefined = undefined;
  private visibleReply: string = '';
  private visibleBody: string = '';

  onPageHide(): void { this.saveReadingPosition(); }

  async aboutToAppear(): Promise<void> {
    try { this.library = await this.storage.open(this.getUIContext().getHostContext() as common.UIAbilityContext); }
    catch { this.message = '本地存储读取失败，请检查设备空间。'; }
    if (this.library.accepted && this.library.rememberToken) {
      try {
        const token = await this.credentials.read();
        if (token) { this.accountName = await this.api.login(token); }
      } catch (error) { if (!this.handleExpired(error as Error)) { this.message = '已保存的账号暂时无法验证，请在账号页重新登录。'; } }
    }
    this.ready = true;
    if (this.library.accepted) { await this.loadFeed(); }
  }
  onBackPress(): boolean {
    if (this.webUrl) {
      try { if (this.webController.accessBackward()) { this.webController.backward(); return true; } } catch {}
      this.webUrl = ''; this.fallbackNotice = ''; return true;
    }
    if (this.selected) { this.closeDetail(); return true; }
    if (this.tab === 2 && this.settingsPage !== 'home') { this.settingsPage = 'home'; this.message = ''; return true; }
    if (this.tab !== 0) { this.tab = 0; return true; }
    return false;
  }
  private bg(): string { return this.library.dark ? '#14201D' : '#F4F5F2'; }
  private card(): string { return this.library.dark ? '#20332B' : '#FFFFFF'; }
  private ink(): string { return this.library.dark ? '#E4EEE7' : '#233D32'; }
  private muted(): string { return this.library.dark ? '#A1B8AB' : '#5C7065'; }
  private handleExpired(error: Error): boolean {
    if (!(error instanceof ApiError) || error.status !== 401) { return false; }
    this.api.logout();
    this.accountName = '';
    this.selected = undefined;
    this.detailRequestId++;
    this.tab = 2;
    this.settingsPage = 'account';
    this.message = '登录已过期，请重新输入令牌。';
    this.credentials.remove().catch(() => { this.message = '登录已过期，已保存的令牌删除失败，请重试退出。'; });
    return true;
  }
  private async persist(): Promise<void> {
    try { await this.storage.save(this.library); } catch { this.message = '保存失败，请检查设备空间。'; }
  }
  private fallback(site: Site, topicId: string = ''): void {
    this.fallbackNotice = '原生加载失败，已自动切换原站网页。返回后可重试原生阅读。';
    this.webUrl = topicId ? (site === 'v2ex' ? `https://www.v2ex.com/t/${topicId}` : `https://linux.do/t/topic/${topicId}`)
      : (site === 'v2ex' ? (this.hot ? 'https://www.v2ex.com/?tab=hot' : 'https://www.v2ex.com/?tab=all') : (this.hot ? 'https://linux.do/top' : 'https://linux.do/latest'));
  }
  private async loadFeed(append: boolean = false): Promise<void> {
    if (append && (this.busy || this.loadingMore || !this.more)) { return; }
    const generation = ++this.requestId;
    const site = this.site; const page = append ? this.feedPage + 1 : 0;
    if (append) { this.loadingMore = true; } else { this.busy = true; this.loadingMore = false; /* keep visible data while refreshing */ }
    this.error = '';
    try {
      const rows = await this.api.feed(site, this.hot, page);
      if (generation !== this.requestId) { return; }
      const previous = append ? this.topics : [];
      this.topics = [...previous, ...rows.filter((item: Topic) => !previous.some((old: Topic) => old.id === item.id))];
      this.feedPage = page; this.more = site === 'linuxdo' && rows.length > 0;
    } catch (e) {
      if (generation === this.requestId) {
        this.error = (e as Error).message || '网络不可用，请重试。';
        if (this.library.autoFallback && this.topics.length === 0 && this.tab === 0 && !this.selected && !this.webUrl) { this.fallback(site); }
      }
    }
    finally { if (generation === this.requestId) { this.busy = false; this.loadingMore = false; } }
  }
  private changeFeed(site: Site, hot: boolean): void {
    if (site === this.site && hot === this.hot) { return; }
    const snapshot = new FeedSnapshot();
    snapshot.topics = this.topics;
    snapshot.offset = this.feedOffset;
    snapshot.page = this.feedPage;
    snapshot.more = this.more;
    this.feedSnapshots.set(this.site + ':' + this.hot, snapshot);
    this.requestId++;
    this.busy = false;
    this.loadingMore = false;
    this.site = site;
    this.hot = hot;
    this.error = '';
    const saved = this.feedSnapshots.get(site + ':' + hot);
    this.topics = saved?.topics ?? [];
    this.feedOffset = saved?.offset ?? 0;
    this.feedPage = saved?.page ?? 0;
    this.more = saved?.more ?? false;
    if (!saved) { this.loadFeed(); }
    else { setTimeout(() => { this.feedScroller.scrollTo({ xOffset: 0, yOffset: this.feedOffset }); }, 80); }
  }
  private switchSite(site: Site): void { this.changeFeed(site, this.hot); }
  private markRead(topic: Topic): void {
    this.library.bookmarks = this.library.bookmarks.map((item: Topic) => {
      if (topicKey(item) === topicKey(topic)) { item.read = true; }
      return item;
    });
    this.persist();
  }
  private async openTopic(topic: Topic): Promise<void> {
    this.saveReadingPosition();
    this.markRead(topic);
    if (topic.webOnly) {
      this.webUrl = topic.url;
      this.fallbackNotice = '';
      this.library.history = [topic, ...this.library.history.filter((item: Topic) => topicKey(item) !== topicKey(topic))].slice(0, 100);
      this.persist();
      return;
    }
    this.floorInput = '';
    this.detailLoaded = false;
    this.detailFailed = false;
    this.progressY = undefined;
    this.visibleReply = '';
    this.visibleBody = '';
    const id = ++this.detailRequestId; const epoch = this.api.epoch;
    const shell = new Detail(); shell.topic = topic; this.selected = shell;
    this.message = '正在加载正文与评论…';
    try {
      const detail = await this.api.detail(topic);
      if (id !== this.detailRequestId || epoch !== this.api.epoch) { return; }
      this.selected = detail; this.detailLoaded = true; this.message = '';
      // Only public metadata is recorded; authenticated bodies are memory-only.
      if (!this.accountName || topic.site !== 'v2ex') {
        try { await this.storage.cache(detail); } catch { this.message = '内容已加载，但离线缓存保存失败。'; }
        const summary = new Topic(); summary.site = topic.site; summary.id = topic.id;
        summary.title = topic.title; summary.url = topic.url; summary.category = topic.category;
        summary.author = topic.author; summary.replies = topic.replies;
        this.library.history = [summary, ...this.library.history.filter((t: Topic) => topicKey(t) !== topicKey(topic))].slice(0, 100);
        await this.persist();
      }
    } catch (e) {
      if (id !== this.detailRequestId || epoch !== this.api.epoch) { return; }
      if (this.handleExpired(e as Error)) { return; }
      this.detailFailed = true;
      if (this.library.autoFallback && !this.webUrl) {
        this.message = (e as Error).message || '主题加载失败。';
        this.fallback(topic.site, topic.id); return;
      }
      let cached: Detail | undefined;
      try { if (!this.accountName || topic.site !== 'v2ex') { cached = await this.storage.cached(topic); } } catch {}
      if (id !== this.detailRequestId || epoch !== this.api.epoch) { return; }
      if (cached) { this.selected = cached; this.detailLoaded = true; this.message = '当前显示离线缓存，内容可能不是最新。'; }
      else { this.message = (e as Error).message || '主题加载失败。'; }
    }
  }
  private saveReadingPosition(): void {
    if (this.selected && (!this.accountName || this.selected.topic.site !== 'v2ex')) {
      const key = topicKey(this.selected.topic);
      const position = readingOffsetToSave(this.detailLoaded, this.progressY, this.library.progress[key]);
      if (position !== undefined) {
        this.library.progress[key] = position;
        this.library.replyAnchors[key] = this.visibleReply;
        this.library.bodyAnchors[key] = this.visibleBody;
        this.persist();
      }
    }
  }
  private closeDetail(): void {
    this.saveReadingPosition();
    this.detailRequestId++; this.selected = undefined; this.message = '';
  }
  private async moreReplies(): Promise<void> {
    if (!this.selected || this.loadingMore) { return; }
    const current = this.selected; const id = this.detailRequestId; const epoch = this.api.epoch;
    this.loadingMore = true;
    try {
      let rows: Reply[] = [];
      if (current.topic.site === 'v2ex') { rows = await this.api.vReplies(current.topic.id, current.nextPage); }
      else { rows = await this.api.dReplies(current.topic.id, current.remainingIds.slice(0, 20)); }
      if (id !== this.detailRequestId || epoch !== this.api.epoch) { return; }
      current.replies = [...current.replies, ...rows.filter((r: Reply) => !current.replies.some((old: Reply) => old.id === r.id))]
        .sort((a: Reply, b: Reply) => a.floor - b.floor);
      current.remainingIds = current.remainingIds.slice(20);
      current.nextPage = rows.length > 0 && current.replies.length < current.topic.replies ? current.nextPage + 1 : 0;
      const updated = new Detail(); updated.topic = current.topic; updated.replies = current.replies;
      updated.nextPage = current.nextPage; updated.remainingIds = current.remainingIds; this.selected = updated;
    } catch (e) {
      if (id === this.detailRequestId && epoch === this.api.epoch) {
        if (this.handleExpired(e as Error)) { return; }
        this.message = (e as Error).message;
        if (this.library.autoFallback && !this.webUrl) { this.fallback(current.topic.site, current.topic.id); }
      }
    }
    finally { this.loadingMore = false; }
  }
  private async transferBookmarks(exporting: boolean): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (exporting) {
        const saved = await this.bookmarkFiles.exportFile(context, exportBookmarks(this.library));
        this.message = saved ? '收藏已导出。' : '已取消导出。';
      } else {
        const text = await this.bookmarkFiles.importFile(context);
        if (!text) { this.message = '已取消导入。'; return; }
        const merged = importBookmarks(text, this.library.bookmarks);
        const candidate = JSON.parse(JSON.stringify(this.library)) as Library;
        candidate.bookmarks = merged;
        await this.storage.save(candidate);
        this.library = candidate;
        this.message = '收藏已合并，现有条目保留。';
      }
    } catch (error) { this.message = (error as Error).message || '文件操作失败，请重试。'; }
  }
  private updateBookmark(topic: Topic, tags: string, read: boolean): void {
    this.library.bookmarks = this.library.bookmarks.map((item: Topic) => {
      if (topicKey(item) === topicKey(topic)) {
        item.tags = tags.split(/[,，]/).map((tag: string) => tag.trim()).filter((tag: string) => tag.length > 0).slice(0, 10);
        item.read = read;
      }
      return item;
    });
    this.persist();
  }
  private async copyWebLink(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.webController.getUrl()));
      this.fallbackNotice = '链接已复制。';
    } catch { this.fallbackNotice = '复制失败，请稍后重试。'; }
  }
  private async openExternal(): Promise<void> {
    try {
      const url = this.webController.getUrl();
      if (!url.startsWith('https://')) { this.fallbackNotice = '仅支持打开 HTTPS 链接。'; return; }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.startAbility({ action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'], uri: url });
    } catch { this.fallbackNotice = '无法打开系统浏览器。'; }
  }
  private matchesLibrary(topic: Topic): boolean {
    return (topic.title + ' ' + topic.author + ' ' + topic.url + ' ' + (topic.tags ?? []).join(' ')).toLowerCase().includes(this.libraryQuery.trim().toLowerCase());
  }
  private saveWebPage(): void {
    try {
      const url = this.webController.getUrl();
      if (!url.startsWith('https://')) { this.fallbackNotice = '只能保存 HTTPS 网页。'; return; }
      const topic = new Topic();
      topic.webOnly = true;
      topic.id = url;
      topic.url = url;
      topic.title = this.webController.getTitle() || url;
      topic.category = '原站网页';
      topic.read = true;
      if (!this.bookmarked(topic)) {
        this.library.bookmarks = [topic, ...this.library.bookmarks].slice(0, 200);
        this.persist();
      }
      this.fallbackNotice = '已保存到稍后读。';
    } catch { this.fallbackNotice = '请等网页加载完成后再保存。'; }
  }
  private bodyBlocks(detail: Detail): ArticleBlock[] {
    return articleBlocks(detail.topic.html || '<p>' + detail.topic.body.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>') + '</p>', detail.topic.site);
  }
  private replyStart(detail: Detail): number { return this.bodyBlocks(detail).length + 2; }
  private jumpFloor(detail: Detail, floor: number): void {
    const index = detail.replies.findIndex((reply: Reply) => reply.floor === floor);
    if (index >= 0) {
      this.message = '';
      this.detailScroller.scrollToIndex(index + this.replyStart(detail), false, ScrollAlign.START);
    } else if (detail.topic.site === 'linuxdo' && floor === 1) {
      this.message = '';
      this.detailScroller.scrollToIndex(0);
    } else { this.message = '该楼层还未加载，可继续加载评论或查看原帖。'; }
  }
  private async resumeDetail(detail: Detail): Promise<void> {
    if (this.restoring) { return; }
    this.restoring = true;
    const generation = this.detailRequestId;
    const key = topicKey(detail.topic);
    const anchor = this.library.replyAnchors[key];
    try {
      let current = detail;
      for (let page = 0; anchor && page < 30 && !current.replies.some((reply: Reply) => reply.id === anchor); page++) {
        if (generation !== this.detailRequestId || (!current.nextPage && !current.remainingIds.length)) { break; }
        const count = current.replies.length;
        await this.moreReplies();
        if (generation !== this.detailRequestId || !this.selected) { return; }
        current = this.selected;
        if (current.replies.length === count) { break; }
      }
      if (generation !== this.detailRequestId) { return; }
      const index = current.replies.findIndex((reply: Reply) => reply.id === anchor);
      if (index >= 0) { this.detailScroller.scrollToIndex(index + this.replyStart(current), false, ScrollAlign.START); }
      else {
        const bodyIndex = this.bodyBlocks(current).findIndex((block: ArticleBlock) => block.id === this.library.bodyAnchors[key]);
        if (bodyIndex >= 0 && !anchor) { this.detailScroller.scrollToIndex(bodyIndex + 1, false, ScrollAlign.START); }
        else { this.detailScroller.scrollTo({ xOffset: 0, yOffset: this.library.progress[key] }); }
        if (anchor) { this.message = '本次未找到原评论，已恢复近似位置。可加载更多评论后再试。'; }
      }
    } finally { this.restoring = false; }
  }
  private bookmarked(topic: Topic): boolean { return this.library.bookmarks.some((t: Topic) => topicKey(t) === topicKey(topic)); }
  private bookmark(topic: Topic): void {
    if (!topic.webOnly && !this.bookmarked(topic) && this.accountName && topic.site === 'v2ex') { this.message = '当前版本暂不保存登录态内容，请在原站收藏。'; return; }
    if (this.bookmarked(topic)) { this.library.bookmarks = this.library.bookmarks.filter((t: Topic) => topicKey(t) !== topicKey(topic)); }
    else {
      const copy = new Topic(); copy.site = topic.site; copy.id = topic.id; copy.title = topic.title;
      copy.read = true; copy.author = topic.author; copy.category = topic.category; copy.replies = topic.replies; copy.url = topic.url;
      this.library.bookmarks = [copy, ...this.library.bookmarks].slice(0, 200);
    }
    this.persist();
  }
  private async login(): Promise<void> {
    if (this.loginBusy) { return; } this.loginBusy = true; this.message = '';
    try { this.accountName = await this.api.login(this.tokenInput); if (this.library.rememberToken) { await this.credentials.save(this.tokenInput); }
      this.message = this.library.rememberToken ? '已登录，令牌已保存至系统安全存储。' : '已登录，本次会话有效。'; }
    catch (e) { this.message = (e as Error).message; }
    finally { this.tokenInput = ''; this.loginBusy = false; }
  }
  private async logout(): Promise<void> {
    try { await this.credentials.remove(); } catch { this.message = '安全存储清理失败，请重试退出。'; return; }
    this.api.logout(); this.accountName = ''; this.tokenInput = ''; this.detailRequestId++;
    this.selected = undefined; this.message = '已退出 V2EX，恢复游客阅读。';
  }
  @Builder private note(text: string) {
    Text(text).fontSize(13).fontColor(this.muted()).lineHeight(22).padding(14)
      .backgroundColor(this.card()).borderRadius(12).width('100%')
  }
  @Builder private row(topic: Topic) {
    Column({ space: 10 }) {
      Text(topic.webOnly ? '原站网页' : `${topic.site === 'v2ex' ? 'V2EX' : 'Linux.do'} · ${topic.category}`).fontSize(12).fontColor('#348869')
      Text(topic.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%')
      Row() {
        Text(topic.author || '社区主题').fontSize(12).fontColor(this.muted())
        Blank()
        Text(`${topic.replies} 回复`).fontSize(12).fontColor(this.muted())
      }.width('100%')
    }.alignItems(HorizontalAlign.Start).padding(20).width('100%').backgroundColor(this.card()).borderRadius(16)
      .onClick(() => this.openTopic(topic))
  }
  @Builder private feed() {
    Column({ space: 16 }) {
      Text('今天，读点新东西').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%')
      Scroll() {
        Row({ space: 10 }) {
          ForEach(visibleSources(this.library.sourceOrder, this.library.hiddenSources, this.library.sourceLimit), (source: WebSource) => {
            Button(source.name).backgroundColor(this.site === source.id ? '#287661' : this.card())
              .fontColor(this.site === source.id ? '#FFFFFF' : this.ink())
              .onClick(() => {
                if (source.id === 'v2ex') { this.switchSite('v2ex'); }
                else if (source.id === 'linuxdo') { this.switchSite('linuxdo'); }
                else { this.fallbackNotice = ''; this.webUrl = source.url; }
              })
          }, (source: WebSource) => source.id)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      Text('左右滑动选择站点 · 显示数量与顺序可在设置中调整').fontSize(12).fontColor(this.muted()).width('100%')
      if (visibleSources(this.library.sourceOrder, this.library.hiddenSources, this.library.sourceLimit).some((source: WebSource) => source.id === this.site)) {
      Row({ space: 16 }) {
        Button(this.hot ? '最新' : '✓ 最新').backgroundColor(this.card()).fontColor(this.ink()).onClick(() => { this.changeFeed(this.site, false); })
        Button(this.hot ? '✓ 热门' : '热门').backgroundColor(this.card()).fontColor(this.ink()).onClick(() => { this.changeFeed(this.site, true); })
        Blank()
        Button('刷新').backgroundColor(this.card()).fontColor(this.ink()).onClick(() => this.loadFeed())
      }.width('100%')
      if (this.busy) { Text('正在更新，已有内容可继续阅读').fontColor(this.muted()); LoadingProgress().width(36).height(36) }
      if (this.error) {
        this.note(this.error)
        Row({ space: 12 }) {
          Button('重试').onClick(() => this.loadFeed())
          Button('原站阅读').onClick(() => { this.webUrl = this.site === 'v2ex' ? 'https://www.v2ex.com' : 'https://linux.do'; })
        }
      }
      List({ space: 12, scroller: this.feedScroller }) {
        ForEach(this.topics, (topic: Topic) => { ListItem() { this.row(topic) } }, (t: Topic) => topicKey(t))
        ListItem() {
          if (this.more) { Button(this.loadingMore ? '加载中…' : '加载更多').enabled(!this.loadingMore).onClick(() => this.loadFeed(true)) }
          else if (!this.busy && this.topics.length > 0) { this.note('已展示接口当前可用列表') }
        }
      }.layoutWeight(1).width('100%')
        .onDidScroll((_offset: number, state: ScrollState) => { if (state !== ScrollState.Idle) { this.feedOffset = this.feedScroller.currentOffset().yOffset; } })
        .onAppear(() => { const offset = this.feedOffset; setTimeout(() => { if ((!this.selected || useSplitReader(this.windowWidth)) && this.tab === 0) { this.feedScroller.scrollTo({ xOffset: 0, yOffset: offset }); } }, 80); })
      } else {
        this.note('当前原生站点未在显示范围内，请选择上方站点，或在设置中调整数量和显示开关。其他技术站点会打开原站网页。')
        Button('管理站点').onClick(() => { this.settingsPage = 'sites'; this.tab = 2; })
        Blank()
      }
    }.padding({ left: 18, right: 18, top: 10 }).height('100%')
  }
  @Builder private topicView(detail: Detail) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Button('‹ 返回').onClick(() => this.closeDetail()).backgroundColor(this.card()).fontColor(this.ink())
        Blank()
        Button('原帖').onClick(() => { this.webUrl = detail.topic.url; }).backgroundColor(this.card()).fontColor(this.ink())
      }.width('100%')
      if (this.message) { this.note(this.message) }
      if (this.detailFailed) {
        Button('重试正文与评论').onClick(() => { this.saveReadingPosition(); this.openTopic(detail.topic); })
      }
      Row({ space: 10 }) {
        Button(this.bookmarked(detail.topic) ? '已加入稍后读' : '稍后读').onClick(() => this.bookmark(detail.topic))
        if (this.detailLoaded && (!this.accountName || detail.topic.site !== 'v2ex') && (this.library.progress[topicKey(detail.topic)] ?? 0) > 0) {
          Button(this.restoring ? '正在查找原位置…' : '恢复进度').enabled(!this.restoring).onClick(() => this.resumeDetail(detail))
        }
      }
      if (this.detailLoaded && detail.replies.length > 0) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '输入楼层', text: this.floorInput }).type(InputType.Number)
            .layoutWeight(1).onChange((value: string) => { this.floorInput = value; })
          Button('跳转').enabled(Number(this.floorInput) > 0).onClick(() => this.jumpFloor(detail, Number(this.floorInput)))
        }.width('100%')
      }
      List({ space: 16, scroller: this.detailScroller }) {
        ListItem() {
          Column({ space: 16 }) {
            Text(detail.topic.title).fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.ink())
            Text(`${detail.topic.author} · ${detail.topic.category}`).fontSize(13).fontColor(this.muted())
          }.alignItems(HorizontalAlign.Start).width('100%')
        }
        ForEach(this.bodyBlocks(detail), (block: ArticleBlock) => {
          ListItem() {
            Column({ space: 8 }) {
              RichText(richDocument(block.html, '', this.getUIContext().fp2px(this.library.fontSize), this.library.dark, detail.topic.site)).width('100%')
              ReaderTools({ html: block.html, site: detail.topic.site })
            }.width('100%')
          }
        }, (block: ArticleBlock) => block.id)
        ListItem() {
          Text('评论 · 已加载 ' + detail.replies.length + ' / ' + detail.topic.replies).fontSize(18).fontColor(this.ink())
        }
        ForEach(detail.replies, (reply: Reply) => {
          ListItem() {
            Column({ space: 10 }) {
              Text(reply.author + (detail.topic.author && reply.author === detail.topic.author ? '（楼主）' : '') + ' · #' + reply.floor).fontSize(13).fontColor('#348869')
              if (reply.parentFloor > 0) {
                Button('查看回复对象 #' + reply.parentFloor).onClick(() => this.jumpFloor(detail, reply.parentFloor))
              }
              RichText(richDocument(reply.html || '', reply.body, this.getUIContext().fp2px(this.library.fontSize), this.library.dark, detail.topic.site)).width('100%')
              ReaderTools({ html: reply.html, site: detail.topic.site })
            }.alignItems(HorizontalAlign.Start).padding(16).backgroundColor(this.card()).borderRadius(14).width('100%')
          }
        }, (reply: Reply) => reply.id)
        ListItem() {
          if (detail.nextPage > 0 || detail.remainingIds.length > 0) {
            Button(this.loadingMore ? '加载中…' : '加载更多评论').enabled(!this.loadingMore).onClick(() => this.moreReplies())
          }
        }
      }.layoutWeight(1).width('100%').onDidScroll((_offset: number, state: ScrollState) => {
        if (this.detailLoaded && state !== ScrollState.Idle) { this.progressY = this.detailScroller.currentOffset().yOffset; }
      }).onScrollIndex((start: number) => {
        const replyIndex = start - this.replyStart(detail);
        this.visibleReply = replyIndex >= 0 && replyIndex < detail.replies.length ? detail.replies[replyIndex].id : '';
        const blocks = this.bodyBlocks(detail);
        this.visibleBody = start >= 1 && start <= blocks.length ? blocks[start - 1].id : '';
      }).onScrollStop(() => { this.saveReadingPosition(); })
    }.padding(20).height('100%')
  }
  @Builder private libraryView() {
    List({ space: 14 }) {
      ListItem() { Text('我的阅读').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.ink()) }
      ListItem() { this.note('稍后读和历史保存在本机。登录态 V2EX 内容暂不持久保存，避免账号内容混入游客空间。') }
      ListItem() { Text(`稍后读 · ${this.library.bookmarks.length}`).fontSize(19).fontColor(this.ink()) }
      ListItem() {
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索标题、作者或链接', text: this.libraryQuery }).layoutWeight(1)
            .onChange((value: string) => { this.libraryQuery = value; })
          Button(this.unreadOnly ? '仅未读' : '全部').onClick(() => { this.unreadOnly = !this.unreadOnly; })
        }
      }
      ForEach(this.library.bookmarks.filter((topic: Topic) => this.matchesLibrary(topic) &&
        (!this.unreadOnly || !topic.read)), (topic: Topic) => {
        ListItem() {
          Column({ space: 8 }) {
            this.row(topic)
            TextInput({ placeholder: '标签，用逗号分隔', text: (topic.tags ?? []).join(', ') })
              .onChange((value: string) => this.updateBookmark(topic, value, topic.read))
            Row({ space: 10 }) {
              Button(topic.read ? '标为未读' : '标为已读').onClick(() => this.updateBookmark(topic, (topic.tags ?? []).join(','), !topic.read))
              Button('移除').onClick(() => this.bookmark(topic))
            }
          }
        }
      }, (t: Topic) => `b:${topicKey(t)}:${t.read}`)
      ListItem() { Text(`阅读历史 · ${this.library.history.length}`).fontSize(19).fontColor(this.ink()) }
      ForEach(this.library.history.filter((topic: Topic) => this.matchesLibrary(topic)), (topic: Topic) => { ListItem() { this.row(topic) } }, (t: Topic) => `h:${topicKey(t)}`)
      ListItem() { Button('清空历史与进度').onClick(() => { this.library.history = []; this.library.progress = {}; this.library.replyAnchors = {}; this.library.bodyAnchors = {}; this.persist(); }) }
    }.padding(20).height('100%').width('100%')
  }
  @Builder private settingsEntry(title: string, summary: string, destination: string) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink())
        Text(summary).fontSize(13).fontColor(this.muted()).maxLines(2)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(24).fontColor(this.muted())
    }.width('100%').padding(18).backgroundColor(this.card()).borderRadius(14)
      .onClick(() => { this.settingsPage = destination; this.message = ''; })
  }
  private settingsTitle(): string {
    if (this.settingsPage === 'sites') { return '站点管理'; }
    if (this.settingsPage === 'reading') { return '阅读体验'; }
    if (this.settingsPage === 'account') { return '账号'; }
    if (this.settingsPage === 'data') { return '数据管理'; }
    if (this.settingsPage === 'about') { return '关于我们'; }
    return '栈里拾光';
  }
  @Builder private settings() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        if (this.settingsPage !== 'home') {
          Button('‹ 返回').backgroundColor(this.card()).fontColor(this.ink()).onClick(() => { this.settingsPage = 'home'; this.message = ''; })
        }
        Text(this.settingsTitle()).fontSize(this.settingsPage === 'home' ? 28 : 23).fontWeight(FontWeight.Bold).fontColor(this.ink()).layoutWeight(1)
      }.width('100%').padding(20)
      Scroll() {
        Column({ space: 14 }) {
          if (this.settingsPage === 'home') {
            Text('在技术的世界里，拾起值得留住的时光。').fontSize(14).fontColor(this.muted()).width('100%').margin({ bottom: 8 })
            this.settingsEntry('站点管理', '显示 ' + visibleSources(this.library.sourceOrder, this.library.hiddenSources, this.library.sourceLimit).length + ' 个站点 · 数量与顺序', 'sites')
            this.settingsEntry('阅读体验', this.library.fontSize + ' 号字 · ' + (this.library.dark ? '深色' : '浅色') + ' · 失败自动降级' + (this.library.autoFallback ? '已开启' : '未开启'), 'reading')
            this.settingsEntry('账号', this.accountName ? 'V2EX 已登录：' + this.accountName : '游客模式 · 登录为可选', 'account')
            this.settingsEntry('数据管理', '离线缓存、阅读记录与网页会话', 'data')
            this.settingsEntry('关于我们', '名字的故事、应用介绍与隐私说明', 'about')
            Text('栈里拾光 0.1.0').fontSize(12).fontColor(this.muted()).margin({ top: 20 })
          } else if (this.settingsPage === 'sites') {
        Row({ space: 12 }) {
          Text(`最多显示 ${this.library.sourceLimit} 个`).fontColor(this.ink()).layoutWeight(1)
          Button('−').enabled(this.library.sourceLimit > 0).onClick(() => { this.library.sourceLimit--; this.persist(); })
          Button('+').enabled(this.library.sourceLimit < WEB_SOURCES.length).onClick(() => { this.library.sourceLimit++; this.persist(); })
        }.width('100%')
        this.note('先按下方顺序排除隐藏站点，再取前 N 个显示。调整立即生效并自动保存，同时影响主页站点栏与“技术站点”页。主页站点栏可左右滑动。')
        ForEach(orderedSources(this.library.sourceOrder), (source: WebSource, index: number) => {
          Column({ space: 8 }) {
            Row() {
              Text(`${index + 1}. ${source.name}`).fontColor(this.ink()).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: !this.library.hiddenSources.includes(source.id) }).onChange((on: boolean) => {
                this.library.hiddenSources = on ? this.library.hiddenSources.filter((id: string) => id !== source.id)
                  : [...this.library.hiddenSources.filter((id: string) => id !== source.id), source.id];
                this.persist();
              })
            }.width('100%')
            Row({ space: 12 }) {
              Button('上移').enabled(index > 0).onClick(() => { this.library.sourceOrder = moveSource(this.library.sourceOrder, source.id, -1); this.persist(); })
              Button('下移').enabled(index < WEB_SOURCES.length - 1).onClick(() => { this.library.sourceOrder = moveSource(this.library.sourceOrder, source.id, 1); this.persist(); })
            }
          }.padding(12).width('100%').backgroundColor(this.card()).borderRadius(12)
        }, (source: WebSource, index: number) => `${source.id}:${index}`)
        Button('恢复默认站点设置').onClick(() => {
          this.library.sourceOrder = []; this.library.hiddenSources = []; this.library.sourceLimit = WEB_SOURCES.length; this.persist();
        })

          } else if (this.settingsPage === 'reading') {
        Text(`正文字号 · ${this.library.fontSize}`).fontSize(18).fontColor(this.ink())
        Slider({ value: this.library.fontSize, min: 14, max: 24, step: 1 }).onChange((value: number) => { this.library.fontSize = value; this.persist(); })
        Row() {
          Text('深色阅读').fontColor(this.ink()); Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.library.dark }).onChange((on: boolean) => { this.library.dark = on; this.persist(); })
        }.width('100%')
        Row() {
          Text('失败时自动打开原站').fontColor(this.ink()).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.library.autoFallback }).onChange((on: boolean) => { this.library.autoFallback = on; this.persist(); })
        }.width('100%')
        this.note('开启后，V2EX 或 Linux.do 的原生列表、正文、评论请求失败时，会自动用应用内网页打开对应原站页面。默认关闭，设置保存在本机；原站网页失败不会循环跳转。关闭时保留错误提示与离线缓存。')

            Text('阅读预览').fontSize(14).fontColor(this.muted()).width('100%')
            Text('在代码之间，留一点时间读世界。').fontSize(this.library.fontSize).lineHeight(this.library.fontSize * 1.85).fontColor(this.ink()).padding(18).backgroundColor(this.card()).borderRadius(14).width('100%')
          } else if (this.settingsPage === 'account') {
        this.note(this.accountName ? `V2EX · ${this.accountName}` : '当前使用游客模式，无需登录即可阅读公开内容。')
        Row() {
          Text('记住 V2EX 登录').fontColor(this.ink()).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.library.rememberToken }).onChange(async (enabled: boolean) => {
            try {
              if (!enabled) { await this.credentials.remove(); }
              this.library.rememberToken = enabled;
              this.persist();
            } catch { this.message = '安全存储操作失败，请重试。'; }
          })
        }.width('100%')
        if (!this.accountName) {
          TextInput({ placeholder: 'V2EX 个人访问令牌', text: this.tokenInput }).type(InputType.Password).onChange((value: string) => { this.tokenInput = value; })
          Button(this.loginBusy ? '验证中…' : '登录 V2EX').enabled(!this.loginBusy).onClick(() => this.login())
          Button('如何获取令牌').onClick(() => { this.webUrl = 'https://www.v2ex.com/settings/tokens'; })
          this.note('可选将令牌保存在系统安全存储，设备解锁后使用。关闭记住登录或退出时删除保存的令牌。')
        } else { Button('退出 V2EX').onClick(() => this.logout()) }
        Button('Linux.do 原站登录 / 阅读').onClick(() => { this.webUrl = 'https://linux.do/login'; })
        this.note('Linux.do 当前使用原站登录。官方 Connect 接入需要申请应用，身份授权与论坛内容访问权限需分别验证。')

          } else if (this.settingsPage === 'data') {
            Row({ space: 10 }) {
              Button('导出收藏').onClick(() => this.transferBookmarks(true))
              Button('导入收藏').onClick(() => this.transferBookmarks(false))
            }
            this.note('导出文件包含收藏标题、链接、标签和阅读状态，导入时合并重复条目。')
            this.note('清除正文缓存会移除离线内容，稍后读与阅读历史仍保留。')
        Button('清除离线正文缓存').onClick(async () => {
          try { await this.storage.clearCache(); this.message = '离线缓存已清除，稍后读与历史保留。'; }
          catch { this.message = '清除缓存失败，请重试。'; }
        })

        Button('清除原站网页会话').onClick(async () => {
          try { await webview.WebCookieManager.clearAllCookies(); this.message = '网页 Cookie 已清除；网页自身保存的其他数据由系统 Web 组件管理。'; }
          catch { this.message = '网页会话清除失败，请重试。'; }
        })

            Button('清空历史与阅读进度').onClick(() => {
              this.getUIContext().showAlertDialog({ title: '清空阅读记录？', message: '阅读历史和进度将被删除，稍后读仍保留。',
                primaryButton: { value: '取消', action: () => {} },
                secondaryButton: { value: '清空记录', action: () => { this.library.history = []; this.library.progress = {}; this.library.replyAnchors = {}; this.library.bodyAnchors = {}; this.persist(); this.message = '阅读历史与进度已清空。'; } }
              });
            })
          } else if (this.settingsPage === 'about') {
            Text('栈里拾光').fontSize(32).fontWeight(FontWeight.Bold).fontColor(this.ink()).margin({ top: 12 })
            Text('技术好内容，一处慢慢读。').fontSize(17).fontColor('#348869').margin({ bottom: 16 })
            Text('名字的由来').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.ink())
            Text('“栈”是开发者熟悉的技术栈，也是不断积累的知识；“拾光”是在日常的碎片时间里，拾起值得阅读、思考和留存的内容。我们希望，在代码与忙碌之间，为你留下一处安静的阅读空间。').fontSize(16).lineHeight(29).fontColor(this.ink())
            Text('我们在做什么').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.ink()).margin({ top: 12 })
            Text('栈里拾光是一款面向鸿蒙手机的技术社区阅读工具。你可以阅读 V2EX、Linux.do，或从技术站点入口浏览掘金、思否、InfoQ、开源中国、GitHub Trending 和 Hacker News。支持本地稍后读、阅读记录与个性化阅读设置。').fontSize(16).lineHeight(29).fontColor(this.ink())
            Text('尊重每一份分享').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.ink()).margin({ top: 12 })
            Text('我们提供阅读入口，内容归原作者及原站所有。栈里拾光与上述社区不存在官方隶属关系；网页内容和账号权限遵循各站规则。').fontSize(16).lineHeight(29).fontColor(this.ink())
            Text('版本与隐私').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.ink()).margin({ top: 12 })
        this.note('隐私说明：原生请求直接发送至 V2EX 或 Linux.do；技术站点页仅在点击后加载对应网站，网页可能访问其自身服务和链接网站。本应用无自有服务器、广告或统计 SDK；原站网页遵循各自隐私规则。阅读记录保存在设备，卸载后随应用数据删除。')
        this.note('栈里拾光 0.1.0 · 非官方客户端。请遵守社区规则与内容版权。此版本为开发验证版，尚未完成上架审核。')

          }
          if (this.message && this.settingsPage !== 'home') { this.note(this.message) }
        }.padding({ left: 20, right: 20, bottom: 24 }).width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%')
    }.height('100%').width('100%')
  }
  @Builder private sources() {
    Column({ space: 16 }) {
      Text('技术站点').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%')
      this.note('点开后在应用内浏览官方网页。各站账号独立，网页内容、登录及可用性由原站提供；不会自动同步到本地稍后读。')
      Row() {
        Text(`已显示 ${visibleSources(this.library.sourceOrder, this.library.hiddenSources, this.library.sourceLimit).length} 个站点`).fontSize(13).fontColor(this.muted())
        Blank()
        Button('管理显示与排序').onClick(() => { this.settingsPage = 'sites'; this.tab = 2; })
      }.width('100%')
      TextInput({ placeholder: '搜索站点、分类或方向', text: this.sourceFilter }).onChange((value: string) => { this.sourceFilter = value; })
      List({ space: 12 }) {
        ForEach(visibleSources(this.library.sourceOrder, this.library.hiddenSources, this.library.sourceLimit).filter((source: WebSource) => `${source.name} ${source.category} ${source.description}`.toLowerCase().includes(this.sourceFilter.trim().toLowerCase())), (source: WebSource) => {
          ListItem() {
            Column({ space: 8 }) {
              Row() {
                Text(source.name).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.ink())
                Blank()
                Text('原站 ›').fontSize(12).fontColor('#348869')
              }.width('100%')
              Text(source.category).fontSize(12).fontColor('#348869')
              Text(source.description).fontSize(14).fontColor(this.muted())
              Text(source.url).fontSize(11).fontColor(this.muted())
            }.alignItems(HorizontalAlign.Start).padding(18).width('100%').backgroundColor(this.card()).borderRadius(16)
              .onClick(() => { this.fallbackNotice = ''; this.webUrl = source.url; })
          }
        }, (source: WebSource) => source.id)
        if (visibleSources(this.library.sourceOrder, this.library.hiddenSources, this.library.sourceLimit).filter((source: WebSource) => `${source.name} ${source.category} ${source.description}`.toLowerCase().includes(this.sourceFilter.trim().toLowerCase())).length === 0) {
          ListItem() { this.note(this.sourceFilter ? '没有匹配的已显示站点，请清空搜索或到设置调整显示范围。' : '暂无显示站点，请到设置开启站点或增加显示数量。') }
        }
      }.layoutWeight(1).width('100%')
    }.padding(20).height('100%').width('100%')
  }
  private selectTab(tab: number): void {
    if (this.selected) { this.closeDetail(); }
    if (tab === 2) { this.settingsPage = 'home'; this.message = ''; }
    this.tab = tab;
  }
  @Builder private navButton(label: string, tab: number) {
    Button(label).height(48).fontSize(14)
      .fontColor(this.tab === tab ? (this.library.dark ? '#C8ECD9' : '#287661') : this.muted())
      .backgroundColor(this.tab === tab ? (this.library.dark ? '#345747' : '#DCEEE6') : Color.Transparent)
      .width('100%').onClick(() => this.selectTab(tab))
  }
  @Builder private pageContent() {
    if (this.selected) { this.topicView(this.selected) }
    else if (this.tab === 0) { this.feed() }
    else if (this.tab === 1) { this.libraryView() }
    else if (this.tab === 3) { this.sources() }
    else { this.settings() }
  }
  @Builder private appShell() {
    Row() {
      if (useSideNavigation(this.windowWidth)) {
        Column({ space: 12 }) {
          Text('栈里拾光').fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.ink()).margin({ top: 20, bottom: 20 })
          this.navButton('阅读', 0)
          this.navButton('我的阅读', 1)
          this.navButton('技术站点', 3)
          this.navButton('设置', 2)
          Blank()
        }.width(104).height('100%').padding(8).backgroundColor(this.card())
      }
      Column() {
        Row() {
          if (useSplitReader(this.windowWidth) && this.selected && this.tab === 0) {
            Column() { this.feed() }.width(350).height('100%')
            Divider().vertical(true).height('100%')
          }
          Row() {
            Column() { this.pageContent() }
              .width(readerPaneWidth(this.windowWidth, useSplitReader(this.windowWidth) && !!this.selected && this.tab === 0))
              .height('100%')
          }.layoutWeight(1).height('100%').justifyContent(FlexAlign.Center)
        }.layoutWeight(1).width('100%')
        if (!useSideNavigation(this.windowWidth) && !this.selected) {
          Row({ space: 4 }) {
            Column() { this.navButton('阅读', 0) }.layoutWeight(1)
            Column() { this.navButton('我的阅读', 1) }.layoutWeight(1)
            Column() { this.navButton('技术站点', 3) }.layoutWeight(1)
            Column() { this.navButton('设置', 2) }.layoutWeight(1)
          }.padding(8).backgroundColor(this.card()).width('100%')
        }
      }.layoutWeight(1).height('100%')
    }.width('100%').height('100%')
  }
  build() {
    Column() {
      if (!this.ready) { LoadingProgress().width(48).height(48) }
      else if (!this.library.accepted) {
        Column({ space: 24 }) {
          Text('欢迎使用栈里拾光').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.ink())
          this.note('这是用于阅读 V2EX、Linux.do 并浏览其他技术站点的非官方客户端。游客可阅读公开内容，登录为可选。应用仅在你同意后连接社区；其他站点仅在点击后加载。各站服务器会接收正常网络请求信息。')
          this.note('稍后读、历史和阅读设置保存本机。没有自有服务端、广告或统计 SDK。登录凭据不写入日志。点击原站页面时适用原站规则。')
          Button('同意并以游客开始').onClick(async () => { this.library.accepted = true; await this.persist(); await this.loadFeed(); })
          Text('不同意可直接退出应用').fontSize(13).fontColor(this.muted())
        }.padding(28).height('100%').justifyContent(FlexAlign.Center)
      } else if (this.webUrl) {
        Row() {
          Button('‹ 返回应用').onClick(() => { this.webUrl = ''; this.fallbackNotice = ''; })
          Blank()
          Button('稍后读').onClick(() => this.saveWebPage())
          Button('工具').onClick(() => { this.webTools = !this.webTools; })
          Button('刷新').onClick(() => { try { this.webController.refresh(); } catch { this.fallbackNotice = '网页尚未就绪，请稍后重试。'; } })
        }.padding(12).width('100%')
        if (this.fallbackNotice) { this.note(this.fallbackNotice) }
        if (this.webTools) {
          Row({ space: 8 }) {
            Button('复制链接').onClick(() => this.copyWebLink())
            Button('浏览器打开').onClick(() => this.openExternal())
          }.padding(8)
          Row({ space: 8 }) {
            Button('字小').enabled(this.library.webZoom > 70).onClick(() => { this.library.webZoom -= 10; this.persist(); })
            Text(this.library.webZoom + '%').fontColor(this.ink())
            Button('字大').enabled(this.library.webZoom < 200).onClick(() => { this.library.webZoom += 10; this.persist(); })
          }.padding(8)
          Row({ space: 6 }) {
            TextInput({ placeholder: '页内查找', text: this.webSearch }).layoutWeight(1)
              .onChange((value: string) => { this.webSearch = value; })
            Button('查找').onClick(() => {
              try { if (this.webSearch.trim()) { this.webController.searchAllAsync(this.webSearch); } else { this.webController.clearMatches(); } }
              catch { this.fallbackNotice = '网页未就绪。'; }
            })
            Button('下一个').onClick(() => { try { this.webController.searchNext(true); } catch {} })
          }.padding(8)
        }
        if (this.webProgress < 100) { Progress({ value: this.webProgress, total: 100, type: ProgressType.Linear }).width('100%') }
        Web({ src: this.webUrl, controller: this.webController }).javaScriptAccess(true).domStorageAccess(true)
          .textZoomRatio(this.library.webZoom)
          .onProgressChange((event) => { this.webProgress = event.newProgress; })
          .onErrorReceive((event) => { if (event.request.isMainFrame()) { this.fallbackNotice = '网页加载失败，请检查网络后刷新。'; } })
          .layoutWeight(1)
      } else { this.appShell() }
    }.width('100%').height('100%').backgroundColor(this.bg())
      .onAreaChange((_oldArea: Area, area: Area) => {
        const width = Number(area.width);
        if (Number.isFinite(width) && width > 0 && width !== this.windowWidth) {
          this.saveReadingPosition();
          this.windowWidth = width;
        }
      })
  }
}
