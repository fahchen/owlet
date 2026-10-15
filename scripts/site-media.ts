// Regenerates the screenshots on the website from the real app views and the preview fixtures.
// Glass is composited by the window server, so this needs an unlocked screen and Screen Recording
// permission for the terminal. Only the preview's own windows are captured, never the desktop.
// Needs ffmpeg and cwebp (Homebrew `ffmpeg`, `webp`); run with `bun scripts/site-media.ts`.
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const out = join(root, "site/media");
const work = mkdtempSync(join(tmpdir(), "owlet-site-"));

const run = (command: string, args: string[]) => execFileSync(command, args, { stdio: ["ignore", "inherit", "inherit"] });
const preview = (...args: string[]) => run("python3", [join(root, "scripts/panel-preview.py"), ...args]);
const ffmpeg = (...args: string[]) => run("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", ...args]);
// The local ffmpeg has no WebP encoder; libwebp's own tool does the last step.
const webp = (png: string, target: string) => run("cwebp", ["-quiet", "-q", "90", "-m", "6", "-alpha_q", "100", png, "-o", target]);

function size(file: string): { width: number; height: number } {
  const [width, height] = execFileSync("ffprobe", [
    "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", file,
  ]).toString().trim().split(",").map(Number);
  return { width, height };
}

/** The panel's glass, cut out of its window by the frame the preview recorded, corners transparent. */
function panel(shot: string, target: string): void {
  const frame = JSON.parse(readFileSync(shot.replace(/\.png$/, ".json"), "utf8"));
  const scale = size(shot).width / frame.window;
  const [x, y, w, h] = [frame.x, frame.y, frame.width, frame.height].map((v: number) => Math.round(v * scale));
  // PanelMetrics.cornerRadius. Alpha falls off over one pixel at the corner arcs, so the edge is smooth.
  const r = Math.round(34 * scale);
  const dx = `max(0,max(${r}-X,X-${w - 1 - r}))`;
  const dy = `max(0,max(${r}-Y,Y-${h - 1 - r}))`;
  const alpha = `clip((${r}+0.5-hypot(${dx},${dy}))*255,0,255)`;
  ffmpeg("-i", shot, "-vf", `crop=${w}:${h}:${x}:${y},format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='${alpha}'`, target);
}

/** The last row that differs from the bottom-left pixel, so a tall offscreen canvas can be trimmed. */
function contentBottom(file: string): number {
  const { width, height } = size(file);
  const data = execFileSync("ffmpeg", ["-v", "error", "-i", file, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], {
    maxBuffer: width * height * 3 + 1024,
  });
  const at = (x: number, y: number) => (y * width + x) * 3;
  const blank = data.subarray(at(2, height - 2), at(2, height - 2) + 3);
  for (let y = height - 1; y >= 0; y--) {
    for (let x = 0; x < width; x++) {
      const i = at(x, y);
      if (data[i] !== blank[0] || data[i + 1] !== blank[1] || data[i + 2] !== blank[2]) return y + 1;
    }
  }
  return height;
}

try {
  mkdirSync(out, { recursive: true });

  // A plain backdrop: the glass has nothing to pick up, and the panel cuts out cleanly.
  const backdrop = join(work, "backdrop.png");
  ffmpeg("-f", "lavfi", "-i", "color=c=0xf2f2f5:s=2060x1100", "-frames:v", "1", backdrop);
  const shots = join(work, "shots");
  preview("--screenshots", shots, "--background", backdrop);

  for (const [name, target] of [["success", "translate"], ["learning", "learn"], ["learning-selected", "collect"]]) {
    const cut = join(work, `${target}.png`);
    panel(join(shots, `${name}.png`), cut);
    webp(cut, join(out, `${target}.webp`));
    if (target === "translate") {
      // Link previews want a 1200x630 PNG; the translated panel on white is the page in one look.
      ffmpeg("-f", "lavfi", "-i", "color=c=white:s=1200x630", "-i", cut, "-filter_complex",
        "[1]scale=1040:-1:flags=lanczos[p];[0][p]overlay=(W-w)/2:(H-h)/2", "-frames:v", "1", join(out, "og.png"));
    }
    console.log(target);
  }

  // The main window's pages and the Language pane. The window is captured with a solid window right
  // behind it, so its translucent sidebar never shows the desktop.
  const app = join(work, "app");
  preview("--app-shots", app);
  for (const name of ["notebook", "history"]) webp(join(app, `${name}.png`), join(out, `${name}.webp`));
  const pane = join(app, "settings-language.png");
  const { width, height } = size(pane);
  const bottom = Math.min(height, contentBottom(pane) + 48);
  const trimmed = join(work, "languages.png");
  ffmpeg("-i", pane, "-vf", `crop=${width}:${bottom}:0:0`, trimmed);
  webp(trimmed, join(out, "languages.webp"));
  console.log("app shots", width, bottom);
} finally {
  rmSync(work, { recursive: true, force: true });
}
