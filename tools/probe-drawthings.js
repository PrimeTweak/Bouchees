#!/usr/bin/env node
/* curl versus Node, same request.
 *   node tools/probe-drawthings.js
 *
 * The JSON my adapter sends is byte-for-byte what a curl that produces a clean
 * photo sends — printed and compared. Yet the adapter gets an embossed
 * anaglyph and curl does not. So the difference is not the body; it is the
 * HTTP conversation around it.
 *
 * Node's fetch adds headers curl does not: accept-encoding for compressed
 * responses, and keep-alive. Either can corrupt a multi-megabyte body if the
 * server mishandles it — and Draw Things is a desktop app with a minimal HTTP
 * implementation, not a hardened server.
 *
 * This sends the SAME body three ways and writes three files to compare.
 */
"use strict";
const fs = require("fs");
const http = require("http");

const BASE = process.env.DRAWTHINGS_URL || "http://127.0.0.1:7859";
const url = new URL(BASE + "/sdapi/v1/txt2img");

const body = JSON.stringify({
  prompt: "A homemade breakfast dish served in an everyday bowl on a kitchen table. " +
    "clearly visible: wheat flour, rolled oats, cow's milk, canola oil, mashed banana, egg. " +
    "slightly overhead at 60 degrees, one corner of the table visible. " +
    "morning light through a kitchen window. candid home food photography, " +
    "shot in a real family kitchen, not a studio, soft natural window light, " +
    "warm and slightly uneven, worn wooden table or kitchen counter, everyday ceramic dishware, " +
    "shallow depth of field, 50mm lens, gentle background blur, " +
    "a few crumbs and a rumpled dish towel nearby, lived-in and unstyled, " +
    "realistic toddler-sized portion, honest home cooking, natural colours, " +
    "no colour grading, no glossy magazine styling",
  negative_prompt: "no whole nuts, no whole grapes, no candy, no text, no logos, no watermark, " +
    "no people, no hands, no faces, no polished silverware, no black background, " +
    "no studio lighting, no artificial steam, no garnish that is not listed, " +
    "blurry, grainy, noisy, distorted, deformed, low quality, oversaturated, " +
    "plastic looking, cgi, illustration, cartoon, no visible cheese, cream or butter, " +
    "no visible egg, no visible peanuts, no visible tree nuts, whole or chopped, " +
    "no visible bread or wheat pasta, no visible soy sauce, no visible sesame seeds, " +
    "no visible fish, no visible shellfish, no visible mustard, no bright orange dried fruit",
  width: 1664, height: 1104, steps: 8
});

function write(nom, base64) {
  const b = Buffer.from(base64, "base64");
  fs.writeFileSync("/tmp/" + nom + ".png", b);
  const png = b[0] === 0x89 && b.toString("ascii", 1, 4) === "PNG";
  console.log("  " + nom.padEnd(22) + b.length + " bytes · " +
    (png ? b.readUInt32BE(16) + "x" + b.readUInt32BE(20) : "NOT A PNG") +
    "  ->  /tmp/" + nom + ".png");
}

/* 1 — plain Node fetch, exactly what the adapter does today */
async function viaFetch() {
  const rep = await fetch(url.href, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: body
  });
  const d = await rep.json();
  write("node-fetch", d.images[0]);
}

/* 2 — Node fetch with curl's headers: no compression, no keep-alive */
async function viaFetchCurlHeaders() {
  const rep = await fetch(url.href, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Accept": "*/*",
      "Accept-Encoding": "identity",
      "Connection": "close",
      "User-Agent": "curl/8.4.0"
    },
    body: body
  });
  const d = await rep.json();
  write("node-curl-headers", d.images[0]);
}

/* 3 — the raw http module, closest to what curl does on the wire */
function viaHttp() {
  return new Promise(function (resolve, reject) {
    const req = http.request({
      hostname: url.hostname, port: url.port, path: url.pathname, method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
        "Accept": "*/*",
        "User-Agent": "curl/8.4.0",
        "Connection": "close"
      }
    }, function (res) {
      const pieces = [];
      res.on("data", function (c) { pieces.push(c); });
      res.on("end", function () {
        try {
          const d = JSON.parse(Buffer.concat(pieces).toString("utf8"));
          write("node-raw-http", d.images[0]);
          resolve();
        } catch (e) { reject(e); }
      });
    });
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

(async function () {
  console.log("\nSame body, three transports. Open the three files and compare.\n");
  try { await viaFetch(); } catch (e) { console.log("  node-fetch failed: " + e.message); }
  try { await viaFetchCurlHeaders(); } catch (e) { console.log("  node-curl-headers failed: " + e.message); }
  try { await viaHttp(); } catch (e) { console.log("  node-raw-http failed: " + e.message); }
  console.log("\n  open /tmp/node-fetch.png /tmp/node-curl-headers.png /tmp/node-raw-http.png\n");
  console.log("  If the first is an anaglyph and either of the others is clean,");
  console.log("  the transport is the cause and the adapter switches to it.\n");
})();
