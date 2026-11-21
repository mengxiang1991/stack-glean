export function useSideNavigation(width: number): boolean {
  return Number.isFinite(width) && width >= 600;
}
export function useSplitReader(width: number): boolean {
  return Number.isFinite(width) && width >= 1000;
}
export function readerPaneWidth(width: number, split: boolean): number {
  return Math.max(0, Math.min(860, width - (useSideNavigation(width) ? 104 : 0) - (split ? 350 : 0)));
}
