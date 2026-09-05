"use strict";
/* Thumbnails for the week list, made in Node alone. sips only exists on a
 * Mac, and a client with no thumbnail downloaded 2 MB per 66-point square. */

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const SIZE = 480;

/* Reads an 8-bit RGB or RGBA PNG into raw pixels. Palette, 16-bit and
 * interlaced files are refused; the generator never writes those. */
function decode(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
  let pos = 8, width = 0, height = 0, channels = 0, idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos), type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0); height = data.readUInt32BE(4);
      const depth = data[8], color = data[9], interlace = data[12];
      if (depth !== 8 || interlace !== 0) throw new Error("unsupported PNG: depth " + depth + ", interlace " + interlace);
      channels = { 2: 3, 6: 4 }[color];
      if (!channels) throw new Error("unsupported PNG colour type " + color);
    } else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    pos += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * channels, px = Buffer.alloc(stride * height);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const out = px.subarray(y * stride, (y + 1) * stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= channels ? out[i - channels] : 0, b = prev[i], c = i >= channels ? prev[i - channels] : 0;
      let v = line[i];
      if (filter === 1) v += a; else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      out[i] = v & 255;
    }
    prev = out;
  }
  return { width, height, channels, px };
}

/* Box-filter downscale: every output pixel averages the source block it
 * covers. Crisp enough for a 66-point square, and exact for a 2.5x drop. */
function scale(img, target) {
  const ratio = Math.max(img.width, img.height) / target;
  if (ratio <= 1) return img;
  const w = Math.round(img.width / ratio), h = Math.round(img.height / ratio), ch = img.channels;
  const out = Buffer.alloc(w * h * ch);
  for (let y = 0; y < h; y++) {
    const y0 = Math.floor(y * ratio), y1 = Math.min(img.height, Math.floor((y + 1) * ratio));
    for (let x = 0; x < w; x++) {
      const x0 = Math.floor(x * ratio), x1 = Math.min(img.width, Math.floor((x + 1) * ratio));
      const sum = new Array(ch).fill(0);
      let n = 0;
      for (let yy = y0; yy < y1; yy++) for (let xx = x0; xx < x1; xx++) {
        const i = (yy * img.width + xx) * ch;
        for (let k = 0; k < ch; k++) sum[k] += img.px[i + k];
        n++;
      }
      const o = (y * w + x) * ch;
      for (let k = 0; k < ch; k++) out[o + k] = Math.round(sum[k] / n);
    }
  }
  return { width: w, height: h, channels: ch, px: out };
}

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function encode(img) {
  const stride = img.width * img.channels;
  const raw = Buffer.alloc((stride + 1) * img.height);
  for (let y = 0; y < img.height; y++) {
    raw[y * (stride + 1)] = 0;
    img.px.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(img.width, 0); ihdr.writeUInt32BE(img.height, 4);
  ihdr[8] = 8; ihdr[9] = img.channels === 4 ? 6 : 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0))
  ]);
}

/* Makes the thumbnail for one photo; skips it when already newer. Returns
 * "made", "kept" or the error message. */
function thumbnail(root, file) {
  const src = path.join(root, file);
  const dst = path.join(root, file.replace(/^images\//, "images/thumbs/"));
  if (fs.existsSync(dst) && fs.statSync(dst).mtimeMs >= fs.statSync(src).mtimeMs) return "kept";
  try {
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.writeFileSync(dst, encode(scale(decode(fs.readFileSync(src)), SIZE)));
    return "made";
  } catch (e) { return e.message; }
}

/* Every published photo gets its thumbnail. Called by publish.js, so a
 * photo pushed from anywhere ships with one. */
function all(root, files) {
  const tally = { made: 0, kept: 0, failed: [] };
  files.forEach(function (f) {
    const r = thumbnail(root, f);
    if (r === "made") tally.made++; else if (r === "kept") tally.kept++; else tally.failed.push(f + ": " + r);
  });
  return tally;
}

module.exports = { thumbnail, all, SIZE };

if (require.main === module) {
  const root = path.join(__dirname, "..");
  const files = fs.readdirSync(path.join(root, "images")).filter(function (f) { return /\.png$/i.test(f); })
    .map(function (f) { return "images/" + f; });
  const t = all(root, files);
  console.log("thumbnails: " + t.made + " made, " + t.kept + " kept" + (t.failed.length ? ", " + t.failed.length + " failed" : ""));
  t.failed.forEach(function (f) { console.log("  x " + f); });
}
