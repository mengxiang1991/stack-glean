import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export class BookmarkFiles {
  async exportFile(context: common.UIAbilityContext, text: string): Promise<boolean> {
    const view = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = ['stack-glean-bookmarks.json'];
    const files = await view.save(options);
    if (files.length === 0) { return false; }
    const file = fileIo.openSync(files[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, text); } finally { fileIo.closeSync(file); }
    return true;
  }
  async importFile(context: common.UIAbilityContext): Promise<string> {
    const view = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    const files = await view.select(options);
    if (files.length === 0) { return ''; }
    const file = fileIo.openSync(files[0], fileIo.OpenMode.READ_ONLY);
    try {
      if (fileIo.statSync(file.fd).size > 2000000) { throw new Error('导入文件过大。'); }
      const size = fileIo.statSync(file.fd).size;
      const buffer = new ArrayBuffer(size);
      const count = fileIo.readSync(file.fd, buffer);
      return new util.TextDecoder().decodeWithStream(new Uint8Array(buffer.slice(0, count)));
    } finally { fileIo.closeSync(file); }
  }
}
