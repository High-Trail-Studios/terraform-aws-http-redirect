// Unit tests for the CloudFront Function, run with `node --test tests/function`.
// The template is rendered the same way Terraform's templatefile() renders it,
// then executed in an isolated context with a CloudFront-shaped event.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const template = readFileSync(
  new URL("../../src/redirect.js.tftpl", import.meta.url),
  "utf8",
);

function render({ target, code = 301, preservePath = true }) {
  const vars = {
    target_json: JSON.stringify(target),
    redirect_code: String(code),
    preserve_path: String(preservePath),
  };
  const code_ = template.replace(/\$\{(\w+)\}/g, (match, name) => {
    if (!(name in vars)) throw new Error(`unrendered template variable ${match}`);
    return vars[name];
  });
  const context = vm.createContext({});
  vm.runInContext(code_, context);
  const handler = context.handler;
  handler.context = context;
  return handler;
}

function event(uri = "/", querystring = {}) {
  return {
    version: "1.0",
    context: { eventType: "viewer-request" },
    viewer: { ip: "192.0.2.1" },
    request: { method: "GET", uri, querystring, headers: {}, cookies: {} },
  };
}

const location = (res) => res.headers.location.value;

test("template has no Terraform variables left unrendered", () => {
  const handler = render({ target: "https://new.example.org" });
  assert.equal(typeof handler, "function");
});

test("redirects root to target", () => {
  const res = render({ target: "https://new.example.org" })(event("/"));
  assert.equal(res.statusCode, 301);
  assert.equal(res.statusDescription, "Moved Permanently");
  assert.equal(location(res), "https://new.example.org/");
});

test("preserves path", () => {
  const res = render({ target: "https://new.example.org" })(event("/a/b.html"));
  assert.equal(location(res), "https://new.example.org/a/b.html");
});

test("preserves path under a target path", () => {
  const res = render({ target: "https://new.example.org/blog" })(event("/post-1"));
  assert.equal(location(res), "https://new.example.org/blog/post-1");
});

test("preserves single, empty, and multi-value query parameters", () => {
  const res = render({ target: "https://new.example.org" })(
    event("/s", {
      q: { value: "hello%20world" },
      flag: { value: "" },
      tag: { value: "b", multiValue: [{ value: "a" }, { value: "b" }] },
    }),
  );
  assert.equal(location(res), "https://new.example.org/s?q=hello%20world&flag&tag=a&tag=b");
});

test("omits '?' when there is no query string", () => {
  const res = render({ target: "https://new.example.org" })(event("/x", {}));
  assert.equal(location(res), "https://new.example.org/x");
});

test("tolerates a missing querystring object", () => {
  const e = event("/x");
  delete e.request.querystring;
  assert.equal(location(render({ target: "https://new.example.org" })(e)), "https://new.example.org/x");
});

test("preserve_path = false sends everything to the exact target", () => {
  const handler = render({
    target: "https://new.example.org/landing?src=old",
    preservePath: false,
  });
  const res = handler(event("/deep/link", { a: { value: "1" } }));
  assert.equal(location(res), "https://new.example.org/landing?src=old");
});

for (const [code, description] of [
  [301, "Moved Permanently"],
  [302, "Found"],
  [307, "Temporary Redirect"],
  [308, "Permanent Redirect"],
]) {
  test(`status ${code}`, () => {
    const res = render({ target: "https://new.example.org", code })(event("/"));
    assert.equal(res.statusCode, code);
    assert.equal(res.statusDescription, description);
  });
}

test("target string is embedded safely (no code injection via target_url)", () => {
  const target = 'https://new.example.org/a";globalThis.pwned=1;"';
  const handler = render({ target, preservePath: false });
  assert.equal(location(handler(event("/"))), target);
  assert.equal(handler.context.pwned, undefined);
});

test("rendered function stays under the 10 KB CloudFront Functions limit", () => {
  assert.ok(Buffer.byteLength(template, "utf8") < 10 * 1024);
});
