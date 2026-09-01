#!/usr/bin/env node
/* Draw Things silently clamps to whatever the selected model and the machine
 * allow, so the manifest could claim 1664 px while the file was half that —
 * and the size gate, reading the manifest, waved it through. */
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");

/* Same header reader as the image adapter, kept standalone so this tool works
 * even when nothing else does. */
function imageSize(buf) {
  if (!buf || buf.length < 32) return null;
  if (buf[0] === 0x89 && buf.toString("ascii", 1, 4) === "PNG") {
    return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
  }
  if (buf.toString("ascii", 0, 4) === "RIFF" && buf.toString("ascii", 8, 12) === "WEBP") {
    const type = buf.toString("ascii", 12, 16);
    if (type === "VP8X") return { width: buf.readUIntLE(24, 3) + 1, height: buf.readUIntLE(27, 3) + 1 };
    if (type === "VP8 ") return { width: buf.readUInt16LE(26) & 0x3fff, height: buf.readUInt16LE(28) & 0x3fff };
    if (type === "VP8L") {
      const b = buf.readUInt32LE(21);
      return { width: (b & 0x3fff) + 1, height: ((b >> 14) & 0x3fff) + 1 };
    }
    return null;
  }
  if (buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i < buf.length - 9) {
      if (buf[i] !== 0xff) { i++; continue; }
      const marker = buf[i + 1];
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
        return { height: buf.readUInt16BE(i + 5), width: buf.readUInt16BE(i + 7) };
      }
      i += 2 + buf.readUInt16BE(i + 2);
    }
  }
  return null;
}

/* What the display actually needs. The view crops before it fills, so a photo
 * narrower than this is upscaled on screen. */
const NEEDED = 1320;   /* iPhone 16 Pro Max: 440pt x 3 */
const IDEAL = 1640;    /* iPad 11": 820pt x 2 */

const dir = path.join(root, "images");
if (!fs.existsSync(dir)) {
  console.log("No images/ folder — nothing generated yet.");
  process.exit(0);
}

let manifest = {};
try { manifest = JSON.parse(fs.readFileSync(path.join(root, "generation/images/manifest.json"), "utf8")); }
catch (e) {}
const claimed = {};
Object.keys(manifest).forEach(function (id) {
  if (manifest[id].fichier) claimed[path.basename(manifest[id].fichier)] = manifest[id].largeur;
});

const files = fs.readdirSync(dir).filter(function (f) { return /\.(png|webp|jpe?g)$/i.test(f); });
if (!files.length) { console.log("images/ is empty."); process.exit(0); }

let tooSmall = 0, lying = 0;
console.log("  real size      manifest   file");
console.log("  ------------   --------   ----");
files.sort().forEach(function (f) {
  const size = imageSize(fs.readFileSync(path.join(dir, f)));
  const said = claimed[f];
  if (!size) { console.log("  unreadable                " + f); return; }

  const flag = size.width < NEEDED ? "  TOO SMALL" : (size.width < IDEAL ? "  ok for iPhone" : "");
  if (size.width < NEEDED) tooSmall++;
  const mismatch = said && said !== size.width ? "  <- manifest says " + said : "";
  if (mismatch) lying++;

  console.log("  " + (size.width + "x" + size.height).padEnd(13) +
    String(said || "-").padEnd(11) + f + flag + mismatch);
});

console.log("");
console.log("  " + files.length + " image(s) · " + tooSmall + " below " + NEEDED + " px · " +
  lying + " disagreeing with the manifest");

if (tooSmall) {
  console.log("");
  console.log("  Photos narrower than " + NEEDED + " px are upscaled on screen. If Draw");
  console.log("  Things was asked for more and returned less, it clamped: check the");
  console.log("  selected model and the resolution set inside the app itself.");
}
process.exit(tooSmall ? 1 : 0);
