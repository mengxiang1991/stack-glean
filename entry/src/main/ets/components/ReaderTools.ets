import { pasteboard } from '@kit.BasicServicesKit';
import { sanitizeContent } from '../domain/RichContent';
import { readable } from '../data/CommunityApi';

@Component
export struct ReaderTools {
  html: string = '';
  site: string = 'v2ex';
  @State private expanded: boolean = false;
  @State private imageUrl: string = '';
  @State private imageScale: number = 1;
  @State private notice: string = '';
  private initialScale: number = 1;

  private images(): string[] {
    const markup = sanitizeContent(this.html, this.site === 'v2ex' ? 'https://www.v2ex.com' : 'https://linux.do');
    const tags = markup.match(/<img src="[^"]+"/g) ?? [];
    return tags.map((tag: string) => tag.slice(10, -1).replace(/&amp;/g, '&'));
  }
  private codeBlocks(): string[] {
    return (this.html.match(/<pre\b[^>]*>[\s\S]*?<\/pre>/gi) ?? []).map((block: string) => readable(block));
  }
  build() {
    Column({ space: 10 }) {
      if (this.images().length > 0 || this.codeBlocks().length > 0) {
        Button(this.expanded ? '收起图片与代码工具' : '图片放大 / 复制代码').onClick(() => { this.expanded = !this.expanded; })
      }
      if (this.expanded) {
        ForEach(this.images(), (url: string, index: number) => {
          Button('放大图片 ' + (index + 1)).onClick(() => { this.imageUrl = url; this.imageScale = 1; })
        }, (url: string, index: number) => url + index)
        ForEach(this.codeBlocks(), (code: string, index: number) => {
          Scroll() { Text(code).fontFamily('monospace').fontSize(16).copyOption(CopyOptions.LocalDevice) }
            .scrollable(ScrollDirection.Horizontal).width('100%').height(130)
          Button('复制代码 ' + (index + 1)).onClick(async () => {
            try {
              await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code));
              this.notice = '代码已复制。';
            } catch { this.notice = '复制失败，请重试。'; }
          })
        }, (_code: string, index: number) => String(index))
      }
      if (this.imageUrl) {
        Row({ space: 8 }) {
          Button('关闭图片').onClick(() => { this.imageUrl = ''; })
          Button('重置缩放').onClick(() => { this.imageScale = 1; })
        }
        Scroll() {
          Image(this.imageUrl).width('100%').height(420).objectFit(ImageFit.Contain)
            .scale({ x: this.imageScale, y: this.imageScale })
            .gesture(PinchGesture().onActionStart(() => { this.initialScale = this.imageScale; })
              .onActionUpdate((event: GestureEvent) => { this.imageScale = Math.min(5, Math.max(1, this.initialScale * event.scale)); }))
        }.width('100%').height(440).scrollable(ScrollDirection.Free)
      }
      if (this.notice) { Text(this.notice).fontSize(13) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
