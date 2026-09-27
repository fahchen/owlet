// Ego Lite payload; run with: node design/screenshot.mjs
const fs = await import('node:fs/promises');
const path = await import('node:path');
const assert = (await import('node:assert/strict')).default;
const directory = designDirectory;
let html = await fs.readFile(path.join(directory, 'index.html'), 'utf8');
for (const filename of ['owlet.png', 'owlet-mark-white.png']) {
  const data = await fs.readFile(path.join(directory, 'logo', filename));
  html = html.replaceAll(`logo/${filename}`, `data:image/png;base64,${data.toString('base64')}`);
}
const task = await taskSpace(captureSpace ?? 'Owlet design screenshots');
console.log({ spaceId: task.spaceId });
const page = task.page('p1');
await page.cdp('Emulation.setDeviceMetricsOverride', {
  width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false,
});
// A blank document uses default demo data without reading saved preferences or URL size limits.
await page.goto('about:blank');
const { frameTree } = await page.cdp('Page.getFrameTree');
await page.cdp('Page.setDocumentContent', { frameId: frameTree.frame.id, html });
await page.evaluate(async () => { await document.fonts.ready; });
const scenarios = await page.evaluate(() => states);
assert(scenarios.length > 0, 'No design states found');
assert.equal(new Set(scenarios.map(([id]) => id)).size, scenarios.length);
const rows = [];
for (const [id, name, description, filename] of scenarios) {
  const clip = await page.evaluate(async (id) => {
    prefs.translationLayout = ['aligned', 'long'].includes(id) ? 'aligned' : 'separate';
    openExperience(id);
    document.getAnimations().forEach(animation => animation.cancel());
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const element = document.querySelector(id === 'menubar' ? '#menubar' : '#window');
    const rect = element.getBoundingClientRect();
    const x = Math.max(0, Math.floor(rect.left) - 24);
    const y = Math.max(0, Math.floor(rect.top) - 24);
    return {
      x, y,
      width: Math.min(innerWidth, Math.ceil(rect.right) + 24) - x,
      height: Math.min(innerHeight, Math.ceil(rect.bottom) + 24) - y,
    };
  }, id);
  assert(clip.width > 48 && clip.height > 0, `${id}: empty capture`);
  await page.screenshot({ path: path.join(directory, 'screenshots', filename), clip });
  const bytes = await fs.readFile(path.join(directory, 'screenshots', filename));
  assert.equal(bytes.subarray(1, 4).toString(), 'PNG', `${id}: invalid PNG`);
  rows.push(`| [${filename}](screenshots/${filename}) | ${name} | ${description} |`);
  console.log(filename);
}
await fs.writeFile(path.join(directory, 'README.md'), [
  '# Design screenshots', '',
  'Source: `index.html`. One PNG per state; repeated flow-board states are captured once.', '',
  'Screenshot filenames are defined in the fourth field of each `states` entry in `index.html`.', '',
  'Regenerate from the repository root with Ego Lite running:', '',
  '```sh', 'node design/screenshot.mjs', '```', '',
  'Captures use default demo data, a 1440 x 1000 viewport, and native window bounds with 24px padding.',
  'Scrollable content retains its designed viewport; the Prompt state opens its corresponding settings section.', '',
  '| State / screenshot | Name | Notes |', '| --- | --- | --- |', ...rows, '',
].join('\n'));
await task.finish({ keep: [] });
console.log(`Saved ${rows.length} screenshots to design/screenshots/`);
