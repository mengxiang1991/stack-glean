// Runs the real data-layer sources with a mocked HarmonyOS transport.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const studio = process.env.DEVECO_STUDIO || 'C:/Program Files/Huawei/DevEco Studio';
const ts = require(path.join(studio, 'tools/hvigor/hvigor/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
let response = {}; let status = 200; let destroyed = 0; const calls = [];
const network = { http: { RequestMethod: { GET: 'GET' }, createHttp: () => ({
  request: async (url, options) => { calls.push({ url, options }); return { responseCode: status, result: JSON.stringify(response) }; },
  destroy: () => destroyed++
}) } };
const modules = new Map();
const disk = new Map();
const prefs = { get: async (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
  put: async (key, value) => { disk.set(key, value); }, delete: async key => { disk.delete(key); }, flush: async () => {} };
function load(file) {
  if (modules.has(file)) return modules.get(file);
  const module = { exports: {} }; modules.set(file, module.exports);
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInNewContext(`(function(require,module,exports){${code}\n})`, { console })(name => {
    if (name === '@kit.NetworkKit') return network;
    if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => prefs } };
    if (name === '@kit.AbilityKit') return {};
    return load(path.resolve(path.dirname(file), name + '.ets'));
  }, module, module.exports);
  return module.exports;
}
(async () => {
  const { CommunityApi, readable } = load(path.join(root, 'data/CommunityApi.ets'));
  const { sanitizeContent, richDocument } = load(path.join(root, 'domain/RichContent.ets'));
  const { orderedSources, visibleSources, moveSource } = load(path.join(root, 'domain/WebSources.ets'));
  assert.equal(orderedSources(['github', 'github', 'removed'])[0].id, 'github');
  assert.equal(orderedSources(['github', 'github', 'removed']).length, 8);
  assert.equal(visibleSources(['github', 'infoq'], ['github'], 2).map(s => s.id).join(','), 'infoq,v2ex');
  assert.equal(visibleSources([], [], 0).length, 0);
  assert.equal(moveSource([], 'v2ex', -1)[0], 'v2ex');
  assert.equal(moveSource([], 'linuxdo', -1)[0], 'linuxdo');
  assert.equal(moveSource([], 'v2ex', 1)[1], 'v2ex');
  const safe = sanitizeContent('<p onclick="bad()">Hello <strong>world</strong></p><script>bad()</script><img src="/photo.png" onerror="bad()"><a href="javascript:bad()">bad</a><iframe src="https://bad.test">evil</iframe>', 'https://linux.do');
  assert.ok(safe.includes('<strong>world</strong>')); assert.ok(safe.includes('src="https://linux.do/photo.png"'));
  assert.ok(!/onclick|onerror|javascript:|script|iframe|evil/.test(safe));
  assert.ok(sanitizeContent('<pre><code>a &lt; b</code></pre><blockquote>quote</blockquote>', 'https://linux.do').includes('<pre><code>'));
  assert.ok(!sanitizeContent('<img src="http://insecure.test/a"><img src="data:image/svg+xml,bad">', 'https://linux.do').includes('<img'));
  assert.ok(richDocument('', '<script>alert(1)</script>', 17, true, 'v2ex').includes('&lt;script&gt;'));
  const { Topic, Detail, Library } = load(path.join(root, 'domain/Models.ets'));
  assert.equal(readable('<script>secret()</script><p>A &amp; B</p><p>&lt;code&gt;</p>'), 'A & B\n\n<code>');
  const api = new CommunityApi();
  response = [{ id: 12, title: 'Topic', content: 'Body', replies: 0, member: { username: 'a' }, node: { title: 'Node' } }];
  const topics = await api.feed('v2ex', false, 0);
  assert.equal(topics[0].id, '12'); assert.equal(topics[0].url, 'https://www.v2ex.com/t/12');
  const before = calls.length; assert.equal((await api.feed('v2ex', false, 1)).length, 0); assert.equal(calls.length, before);
  response = { success: true, result: { username: 'alice' } };
  assert.equal(await api.login('example-token'), 'alice');
  assert.equal(calls.at(-1).options.header.Authorization, 'Bearer example-token');
  api.logout(); assert.equal(api.username, '');
  response = { topic_list: { topics: [{ id: 9, title: 'Linux', posts_count: 5, category_id: 1 }] } };
  const linux = await api.feed('linuxdo', false, 0); assert.equal(linux[0].replies, 4);
  assert.equal(calls.at(-1).options.header.Authorization, undefined);
  response = { id: 9, title: 'Linux', posts_count: 3, post_stream: { posts: [
    { id: 100, username: 'a', post_number: 1, cooked: '<p>Body</p>' },
    { id: 102, username: 'b', post_number: 3, cooked: '<p>Reply</p>' }
  ], stream: [100, 101, 102] } };
  const detail = await api.detail(linux[0]); assert.equal(detail.topic.body, 'Body');
  assert.equal(detail.replies.length, 1); assert.equal(detail.remainingIds.join(','), '101');
  status = 429; await assert.rejects(api.feed('linuxdo', false, 0), /限流/);
  status = 403; await assert.rejects(api.feed('linuxdo', false, 0), /权限/);
  assert.equal(destroyed, calls.length);
  const { LocalStore } = load(path.join(root, 'data/LocalStore.ets'));
  const storage = new LocalStore(); const library = await storage.open({});
  library.accepted = true; library.progress['v2ex:1'] = 120; library.bookmarks = topics;
  await storage.save(library);
  for (let i = 0; i < 25; i++) {
    const d = new Detail(); d.topic = new Topic(); d.topic.id = String(i); d.topic.body = 'cached';
    await storage.cache(d);
  }
  const first = new Topic(); first.id = '0'; const last = new Topic(); last.id = '24';
  assert.equal(await storage.cached(first), undefined);
  assert.equal((await storage.cached(last)).topic.body, 'cached');
  await storage.clearCache(); assert.equal(await storage.cached(last), undefined);
  const restored = await new LocalStore().open({});
  assert.equal(restored.progress['v2ex:1'], 120); assert.equal(restored.bookmarks[0].id, '12');
  assert.equal(restored.accepted, true);
  // Older installed versions have no fallback setting; migrate without losing data.
  assert.equal(restored.autoFallback, false);
  assert.equal(restored.sourceLimit, 8);
  assert.equal(restored.sourceOrder.length, 0);
  restored.sourceOrder = ['github', 'infoq']; restored.hiddenSources = ['infoq']; restored.sourceLimit = 3;
  restored.autoFallback = true; await storage.save(restored);
  const configured = await new LocalStore().open({});
  assert.equal(configured.autoFallback, true);
  assert.equal(configured.sourceLimit, 3); assert.equal(configured.sourceOrder.join(','), 'github,infoq');
  assert.equal(configured.hiddenSources.join(','), 'infoq');
  console.log('PASS: markup safety, V2EX mapping, finite feed, token login/logout, auth isolation, Discourse stream, HTTP errors, transport cleanup');
  console.log('PASS: library persistence, 20-topic cache eviction, cache clearing preserves bookmarks/progress');
  console.log('PASS: rich HTML allowlist, unsafe URL/handler removal, relative images, code/quotes, escaped fallback');
  console.log('PASS: source ordering, move boundaries, visibility/count, old-settings migration and persistence');
})().catch(e => { console.error(e); process.exitCode = 1; });
