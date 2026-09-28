// Inlines design/shared.css and design/shared.js into each design/<page>.html, so a page renders on
// its own — the Suikou preview serves every path from its SPA shell, so a relative <link> or <script
// src> can never load there. Editing happens in the shared files and the page's own state table; run
// this after changing either.
//
//   node scripts/build-design.mjs      (or: mise run design)
import { readFile, writeFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../design/", import.meta.url));
const css = (await readFile(path.join(root, "shared.css"), "utf8")).trimEnd();
const js = (await readFile(path.join(root, "shared.js"), "utf8")).trimEnd();

const pages = (await readdir(root)).filter((f) => f.endsWith(".html") && f !== "index.html");
let changed = 0;
for (const name of pages) {
  const file = path.join(root, name);
  const before = await readFile(file, "utf8");
  const after = before
    .replace(/<style><!--shared-css-->[\s\S]*?<\/style>/,
             `<style><!--shared-css-->\n${css}\n</style>`)
    .replace(/<script><!--shared-js-->[\s\S]*?<\/script>/,
             `<script><!--shared-js-->\n${js}\n</script>`);
  if (after !== before) {
    await writeFile(file, after);
    changed += 1;
  }
  if (!after.includes("<!--shared-css-->") && !after.includes("<!--shared-js-->")) {
    throw new Error(`${name}: the inline markers are gone; restore them before rebuilding`);
  }
}
console.log(`inlined shared.css and shared.js into ${changed} page(s)`);
