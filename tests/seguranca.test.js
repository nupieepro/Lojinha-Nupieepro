'use strict';
/**
 * Testes de segurança "estáticos" da Lojinha. Rodam no CI (workflow Segurança)
 * e localmente: `npm test`. Sem dependências externas.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const RAIZ = path.join(__dirname, '..');
const IGNORAR = new Set(['.git', 'node_modules', 'vendor', 'tests', 'security', 'archive']);

function arquivos(dir, exts, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (IGNORAR.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) arquivos(p, exts, out);
    else if (exts.some(x => e.name.endsWith(x)) && !e.name.endsWith('.min.js')) out.push(p);
  }
  return out;
}
const rel = p => path.relative(RAIZ, p);

test('libs de terceiros batem com o manifesto de integridade', () => {
  const linhas = fs.readFileSync(path.join(RAIZ, 'security/integridade.sha256'), 'utf8').split('\n').filter(Boolean);
  assert.ok(linhas.length > 0);
  for (const l of linhas) {
    const [hash, arq] = l.split(/\s+/);
    const real = crypto.createHash('sha256').update(fs.readFileSync(path.join(RAIZ, arq))).digest('hex');
    assert.equal(real, hash, `${arq} foi alterado. Se intencional: sha256sum vendor/*.js qrcode.min.js > security/integridade.sha256`);
  }
});

test('nenhum segredo commitado', () => {
  const padroes = [
    [/-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----/, 'chave privada'],
    [/sb_secret_[A-Za-z0-9_\-]{10,}/, 'Supabase secret key'],
    [/\bghp_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{30,}\b/, 'token GitHub'],
    [/\bAKIA[0-9A-Z]{16}\b/, 'chave AWS'],
    [/(smtp|app)[_-]?(password|pass)\s*[:=]\s*['"][^'"\s]{8,}['"]/i, 'senha SMTP/app'],
  ];
  for (const f of arquivos(RAIZ, ['.js', '.html', '.json', '.ts', '.sql', '.md', '.yml', '.toml', '.txt'])) {
    const txt = fs.readFileSync(f, 'utf8');
    for (const [re, d] of padroes) assert.ok(!re.test(txt), `${d} em ${rel(f)}`);
    for (const m of txt.matchAll(/eyJ[A-Za-z0-9_\-]+\.([A-Za-z0-9_\-]+)\.[A-Za-z0-9_\-]+/g)) {
      let pl = {};
      try { pl = JSON.parse(Buffer.from(m[1], 'base64url').toString()); } catch (_) {}
      assert.notEqual(pl.role, 'service_role', `service_role key em ${rel(f)}`);
    }
  }
});

test('sem eval / new Function / document.write', () => {
  for (const f of arquivos(RAIZ, ['.js', '.html', '.ts'])) {
    const t = fs.readFileSync(f, 'utf8');
    assert.ok(!/\beval\s*\(/.test(t), `eval() em ${rel(f)}`);
    assert.ok(!/new Function\s*\(/.test(t), `new Function() em ${rel(f)}`);
    assert.ok(!/document\.write\s*\(/.test(t), `document.write() em ${rel(f)}`);
  }
});

test('todo target="_blank" tem rel="noopener"', () => {
  for (const f of arquivos(RAIZ, ['.html', '.js'])) {
    fs.readFileSync(f, 'utf8').split('\n').forEach((l, i) => {
      if (l.includes('target="_blank"')) assert.ok(/noopener/.test(l), `${rel(f)}:${i + 1}`);
    });
  }
});

test('CSP (meta) presente e sem curinga perigoso em index.html e admin.html', () => {
  for (const f of ['index.html', 'admin.html']) {
    const t = fs.readFileSync(path.join(RAIZ, f), 'utf8');
    const m = t.match(/http-equiv="Content-Security-Policy"\s+content="([^"]+)"/);
    assert.ok(m, `${f} sem CSP`);
    const csp = m[1];
    assert.ok(/object-src 'none'/.test(csp), `${f}: object-src deve ser 'none'`);
    assert.ok(/base-uri 'self'/.test(csp), `${f}: base-uri`);
    assert.ok(!/default-src[^;]*\s\*(\s|;|$)/.test(csp), `${f}: default-src curinga`);
    assert.ok(!/script-src[^;]*https?:/.test(csp), `${f}: script-src não deve liberar hosts externos`);
  }
});

test('RPCs admin_* e criar_pedido: nenhuma migration concede EXECUTE a anon para admin_*', () => {
  const dir = path.join(RAIZ, 'supabase/migrations');
  for (const f of fs.readdirSync(dir).filter(x => x.endsWith('.sql'))) {
    const t = fs.readFileSync(path.join(dir, f), 'utf8');
    assert.ok(!/grant\s+execute\s+on\s+function\s+public\.admin_[^;]*\bto\s+[^;]*\banon\b/i.test(t), `${f}: admin_* liberada para anon`);
  }
});
