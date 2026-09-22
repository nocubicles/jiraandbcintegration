// Customer time review web app for bcjiraintegration.
//
// A customer opens <BASE_URL>/review/<accessToken> (the link Business Central e-mails them),
// sees the tasks and hours logged on their project, enters the hours they approve per task,
// and submits. The app talks to Business Central through the custom API pages of the
// bcjiraintegration extension (integrated/jira/v1.0) using a service-to-service Entra app.
//
// Zero dependencies: Node 18+ built-in http and fetch only.

'use strict';

const http = require('node:http');
const { URL } = require('node:url');

const cfg = {
  port: Number(process.env.PORT || 3000),
  tenantId: required('BC_TENANT_ID'),
  environment: required('BC_ENVIRONMENT'),
  companyId: required('BC_COMPANY_ID'),
  clientId: required('AAD_CLIENT_ID'),
  clientSecret: required('AAD_CLIENT_SECRET'),
  brand: process.env.BRAND_NAME || 'Time review',
};

function required(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing environment variable ${name}`);
    process.exit(1);
  }
  return v;
}

const bcBase = `https://api.businesscentral.dynamics.com/v2.0/${cfg.tenantId}/${cfg.environment}/api/integrated/jira/v1.0/companies(${cfg.companyId})`;

// ---------------------------------------------------------------------------
// Business Central client
// ---------------------------------------------------------------------------

let tokenCache = { value: null, expiresAt: 0 };

async function getToken() {
  if (tokenCache.value && Date.now() < tokenCache.expiresAt - 60_000) return tokenCache.value;
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: cfg.clientId,
    client_secret: cfg.clientSecret,
    scope: 'https://api.businesscentral.dynamics.com/.default',
  });
  const res = await fetch(`https://login.microsoftonline.com/${cfg.tenantId}/oauth2/v2.0/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) throw new Error(`Token request failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  tokenCache = { value: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return tokenCache.value;
}

async function bc(method, path, body) {
  const token = await getToken();
  const headers = { Authorization: `Bearer ${token}`, Accept: 'application/json' };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    headers['If-Match'] = '*';
  }
  const res = await fetch(`${bcBase}/${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* non-JSON body */ }
  if (!res.ok) {
    const msg = json?.error?.message || text || res.statusText;
    const err = new Error(msg);
    err.status = res.status;
    throw err;
  }
  return json;
}

const TOKEN_RE = /^[0-9A-F]{32}$/;

async function findReview(token) {
  const data = await bc('GET', `customerReviews?$filter=accessToken eq '${token}'`);
  return data.value?.[0] || null;
}

async function getLines(reviewNo) {
  const data = await bc('GET', `customerReviewLines?$filter=reviewNo eq ${reviewNo}&$orderby=taskNo`);
  return data.value || [];
}

// ---------------------------------------------------------------------------
// HTML
// ---------------------------------------------------------------------------

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function hours(n) {
  return Number(n || 0).toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function layout(title, body) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<style>
  :root { color-scheme: light dark; --fg: #1a1a1a; --bg: #fff; --muted: #666; --line: #ddd; --accent: #0b5cad; --ok: #1a7f37; --warn: #b54708; }
  @media (prefers-color-scheme: dark) { :root { --fg: #eee; --bg: #161616; --muted: #aaa; --line: #333; --accent: #6cb2ff; --ok: #4ade80; --warn: #fbbf24; } }
  body { margin: 0; font: 16px/1.45 system-ui, -apple-system, Segoe UI, Roboto, sans-serif; color: var(--fg); background: var(--bg); }
  main { max-width: 860px; margin: 0 auto; padding: 24px 16px 48px; }
  h1 { font-size: 1.4rem; margin: 0 0 4px; }
  .muted { color: var(--muted); }
  table { width: 100%; border-collapse: collapse; margin: 20px 0; }
  th, td { text-align: left; padding: 10px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
  th { font-weight: 600; font-size: 0.85rem; color: var(--muted); text-transform: uppercase; letter-spacing: .03em; }
  td.num, th.num { text-align: right; white-space: nowrap; }
  input[type=number] { width: 6.5em; padding: 6px 8px; font: inherit; text-align: right; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--fg); }
  input[type=text] { width: 100%; box-sizing: border-box; padding: 6px 8px; font: inherit; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--fg); }
  .task { font-weight: 600; }
  .desc { font-size: 0.95rem; }
  tfoot td { font-weight: 600; border-bottom: none; }
  .actions { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; margin-top: 12px; }
  button { font: inherit; padding: 10px 18px; border-radius: 8px; border: 1px solid var(--accent); background: var(--accent); color: #fff; cursor: pointer; }
  button.secondary { background: transparent; color: var(--accent); }
  .notice { padding: 12px 14px; border-radius: 8px; border: 1px solid var(--line); margin: 16px 0; }
  .notice.ok { border-color: var(--ok); }
  .notice.warn { border-color: var(--warn); }
  @media (max-width: 600px) {
    th.hide, td.hide { display: none; }
    .comment-row td { border-bottom: 1px solid var(--line); }
  }
</style>
</head>
<body><main>${body}</main></body>
</html>`;
}

function reviewPage(review, lines, message) {
  const rows = lines.map(l => `
    <tr>
      <td><div class="task">${esc(l.taskNo)}</div><div class="desc">${esc(l.taskDescription)}</div>
          <input type="text" name="comment_${esc(l.systemId)}" placeholder="Comment (optional)" maxlength="250" value="${esc(l.customerComment)}" style="margin-top:6px"></td>
      <td class="num">${hours(l.loggedHours)}</td>
      <td class="num"><input type="number" name="approved_${esc(l.systemId)}" min="0" max="${Number(l.loggedHours)}" step="0.25"
          value="${Number(l.approvedHours) || Number(l.loggedHours)}" data-logged="${Number(l.loggedHours)}" required></td>
    </tr>`).join('');
  const totalLogged = lines.reduce((s, l) => s + Number(l.loggedHours || 0), 0);
  return layout(`${cfg.brand}: ${review.projectNo}`, `
    <h1>${esc(cfg.brand)}</h1>
    <p class="muted">${esc(review.customerName)} &middot; ${esc(review.projectDescription || review.projectNo)} &middot; review #${esc(review.reviewNo)}</p>
    <p>Below are the hours logged on your project that we would like to invoice. For each task, confirm the hours you approve.
       Reduce the number if you agree to only part of the hours, or set it to 0 if the task should not be billed. Comments are optional.</p>
    ${message ? `<div class="notice warn">${esc(message)}</div>` : ''}
    <form method="post" action="/review/${esc(review.accessToken)}">
      <table>
        <thead><tr><th>Task</th><th class="num">Logged</th><th class="num">Approved</th></tr></thead>
        <tbody>${rows}</tbody>
        <tfoot><tr><td>Total hours</td><td class="num">${hours(totalLogged)}</td><td class="num" id="total-approved">${hours(totalLogged)}</td></tr></tfoot>
      </table>
      <div class="actions">
        <button type="submit">Submit answer</button>
        <button type="button" class="secondary" id="approve-all">Approve all hours</button>
        <button type="button" class="secondary" id="reject-all">Set all to 0</button>
      </div>
    </form>
    <script>
      const inputs = [...document.querySelectorAll('input[type=number]')];
      const total = document.getElementById('total-approved');
      const fmt = n => n.toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      const recalc = () => total.textContent = fmt(inputs.reduce((s, i) => s + (Number(i.value) || 0), 0));
      inputs.forEach(i => i.addEventListener('input', recalc));
      document.getElementById('approve-all').onclick = () => { inputs.forEach(i => i.value = i.dataset.logged); recalc(); };
      document.getElementById('reject-all').onclick = () => { inputs.forEach(i => i.value = 0); recalc(); };
    </script>`);
}

function messagePage(title, text, kind) {
  return layout(`${cfg.brand}`, `<h1>${esc(cfg.brand)}</h1><div class="notice ${kind || ''}">${esc(text)}</div>`);
}

function answeredPage(review, lines) {
  const rows = lines.map(l => `<tr><td><div class="task">${esc(l.taskNo)}</div><div class="desc">${esc(l.taskDescription)}</div>${l.customerComment ? `<div class="desc muted">${esc(l.customerComment)}</div>` : ''}</td>
    <td class="num">${hours(l.loggedHours)}</td><td class="num">${hours(l.approvedHours)}</td></tr>`).join('');
  const sum = k => lines.reduce((s, l) => s + Number(l[k] || 0), 0);
  return layout(`${cfg.brand}: ${review.projectNo}`, `
    <h1>${esc(cfg.brand)}</h1>
    <p class="muted">${esc(review.customerName)} &middot; ${esc(review.projectDescription || review.projectNo)} &middot; review #${esc(review.reviewNo)}</p>
    <div class="notice ok">Thank you, your answer has been recorded${review.answeredOn ? ` on ${esc(new Date(review.answeredOn).toLocaleDateString('en-GB'))}` : ''}.</div>
    <table>
      <thead><tr><th>Task</th><th class="num">Logged</th><th class="num">Approved</th></tr></thead>
      <tbody>${rows}</tbody>
      <tfoot><tr><td>Total hours</td><td class="num">${hours(sum('loggedHours'))}</td><td class="num">${hours(sum('approvedHours'))}</td></tr></tfoot>
    </table>`);
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

function send(res, status, html) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' });
  res.end(html);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', c => { data += c; if (data.length > 256_000) { reject(new Error('Body too large')); req.destroy(); } });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

async function handleGet(res, token) {
  const review = await findReview(token);
  if (!review) return send(res, 404, messagePage('Not found', 'This review link is not valid.', 'warn'));
  const lines = await getLines(review.reviewNo);
  if (review.status !== 'Sent') {
    if (review.status === 'Answered') return send(res, 200, answeredPage(review, lines));
    return send(res, 410, messagePage('Cancelled', 'This review has been cancelled. Please contact us if you have questions.', 'warn'));
  }
  return send(res, 200, reviewPage(review, lines, null));
}

async function handlePost(req, res, token) {
  const review = await findReview(token);
  if (!review) return send(res, 404, messagePage('Not found', 'This review link is not valid.', 'warn'));
  const lines = await getLines(review.reviewNo);
  if (review.status !== 'Sent') return send(res, 409, messagePage('Already answered', 'This review has already been answered.', 'warn'));

  const form = new URLSearchParams(await readBody(req));
  const updates = [];
  for (const line of lines) {
    const raw = form.get(`approved_${line.systemId}`);
    const approved = Number(raw);
    if (raw === null || raw === '' || !Number.isFinite(approved) || approved < 0 || approved > Number(line.loggedHours)) {
      return send(res, 400, reviewPage(review, lines, `Approved hours for ${line.taskNo} must be between 0 and ${hours(line.loggedHours)}.`));
    }
    const comment = (form.get(`comment_${line.systemId}`) || '').slice(0, 250);
    updates.push({ line, approved: Math.round(approved * 100) / 100, comment });
  }

  try {
    for (const u of updates) {
      await bc('PATCH', `customerReviewLines(${u.line.systemId})`, { approvedHours: u.approved, customerComment: u.comment });
    }
    await bc('POST', `customerReviews(${review.systemId})/Microsoft.NAV.submit`, {});
  } catch (e) {
    console.error('submit failed', e);
    return send(res, 502, reviewPage(review, await getLines(review.reviewNo), `Your answer could not be saved: ${e.message}. Please try again.`));
  }
  const after = await findReview(token);
  return send(res, 200, answeredPage(after || review, await getLines(review.reviewNo)));
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/healthz') { res.writeHead(200, { 'Content-Type': 'text/plain' }); return res.end('ok'); }
    const m = url.pathname.match(/^\/review\/([^/]+)\/?$/);
    if (!m) return send(res, 404, messagePage('Not found', 'Page not found.', 'warn'));
    const token = m[1].toUpperCase();
    if (!TOKEN_RE.test(token)) return send(res, 404, messagePage('Not found', 'This review link is not valid.', 'warn'));
    if (req.method === 'GET') return await handleGet(res, token);
    if (req.method === 'POST') return await handlePost(req, res, token);
    res.writeHead(405); res.end();
  } catch (e) {
    console.error(e);
    send(res, 500, messagePage('Error', 'Something went wrong on our side. Please try again later.', 'warn'));
  }
});

server.listen(cfg.port, () => console.log(`review-web listening on :${cfg.port} -> ${cfg.environment}`));
