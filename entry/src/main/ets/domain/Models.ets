export type Site = 'v2ex' | 'linuxdo';
export class Topic {
  site: Site = 'v2ex';
  id: string = '';
  title: string = '';
  author: string = '';
  category: string = '';
  replies: number = 0;
  url: string = '';
  body: string = '';
  html: string = '';
}
export class Reply {
  id: string = '';
  author: string = '';
  floor: number = 0;
  body: string = '';
  html: string = '';
}
export class Detail {
  topic: Topic = new Topic();
  replies: Reply[] = [];
  nextPage: number = 0;
  remainingIds: number[] = [];
}
export class Library {
  bookmarks: Topic[] = [];
  history: Topic[] = [];
  progress: Record<string, number> = {};
  fontSize: number = 17;
  dark: boolean = false;
  accepted: boolean = false;
  autoFallback: boolean = false;
  sourceOrder: string[] = [];
  hiddenSources: string[] = [];
  sourceLimit: number = 8;
}
export function topicKey(t: Topic): string { return `${t.site}:${t.id}`; }
