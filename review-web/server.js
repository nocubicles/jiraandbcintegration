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

// method, path, optional JSON body, optional ETag for If-Match (defaults to "*" when a body is sent).
async function bc(method, path, body, etag) {
  const token = await getToken();
  const headers = { Authorization: `Bearer ${token}`, Accept: 'application/json' };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    headers['If-Match'] = etag || '*';
  }
  const res = await fetch(`${bcBase}/${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* non-JSON body */ }
  if (!res.ok) {
    const err = new Error(json?.error?.message || text || res.statusText);
    err.status = res.status;
    err.code = json?.error?.code;
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

// BC serialises enums on API pages by member name; accept the caption too, to be safe.
const isSent = r => r.status === 'Sent' || r.status === 'Sent for Review';
const isAnswered = r => r.status === 'Answered';

// A review that was reopened keeps the customer's previous answer on its lines. Prefill from that
// answer whenever any line carries one; a fresh review has all zeros and no comments.
const hasStoredAnswer = lines => lines.some(l => Number(l.approvedHours) > 0 || (l.customerComment || '').trim() !== '');

function round2(n) { return Math.round(n * 100) / 100; }

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
  :root { color-scheme: light; --fg: #1a1a1a; --bg: #fff; --muted: #666; --line: #ddd; --accent: #0b5cad; --ok: #1a7f37; --warn: #b54708; }
  body { margin: 0; font: 16px/1.45 system-ui, -apple-system, Segoe UI, Roboto, sans-serif; color: var(--fg); background: var(--bg); }
  main { max-width: 1100px; margin: 0 auto; padding: 24px 16px 48px; }
  .scroll { overflow-x: auto; }
  h1 { font-size: 1.4rem; margin: 0 0 4px; }
  .muted { color: var(--muted); }
  table { width: 100%; border-collapse: collapse; margin: 20px 0; min-width: 720px; }
  th, td { text-align: left; padding: 10px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
  th { font-weight: 600; font-size: 0.85rem; color: var(--muted); text-transform: uppercase; letter-spacing: .03em; }
  td.num, th.num { text-align: right; white-space: nowrap; }
  input[type=number] { width: 6.5em; padding: 6px 8px; font: inherit; text-align: right; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--fg); }
  input[type=text] { width: 100%; box-sizing: border-box; padding: 6px 8px; font: inherit; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--fg); }
  .task { font-weight: 600; }
  th.ask, td.ask { background: #eef5fc; font-weight: 700; border-left: 2px solid var(--accent); border-right: 2px solid var(--accent); }
  th.ask { color: var(--accent); }
  .legend { font-size: 0.9rem; }
  .legend dt { font-weight: 600; display: inline; }
  .legend dd { display: inline; margin: 0 12px 0 4px; }
  .desc { font-size: 0.95rem; }
  tfoot td { font-weight: 600; border-bottom: none; }
  .actions { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; margin-top: 12px; }
  button { font: inherit; padding: 10px 18px; border-radius: 8px; border: 1px solid var(--accent); background: var(--accent); color: #fff; cursor: pointer; }
  button.secondary { background: transparent; color: var(--accent); }
  .notice { padding: 12px 14px; border-radius: 8px; border: 1px solid var(--line); margin: 16px 0; }
  .notice.ok { border-color: var(--ok); }
  .notice.warn { border-color: var(--warn); }
</style>
</head>
<body><main>${body}</main></body>
</html>`;
}

// Columns that describe the task's whole history, as captured when the review was created.
const HISTORY = [
  ['taskLoggedHours', 'Logged'],
  ['taskBilledHours', 'Billed'],
  ['taskNotBillableHours', 'Not billable'],
  ['taskNotBilledHours', 'Not billed'],
];
const requestedOf = l => round2(Number(l.hoursToBill || 0));
const sumOf = (lines, k) => lines.reduce((s, l) => s + Number(l[k] || 0), 0);
const historyCells = l => HISTORY.map(([k]) => `<td class="num">${hours(l[k])}</td>`).join('');
const historyHeads = HISTORY.map(([, t]) => `<th class="num">${t}</th>`).join('');
const historyTotals = lines => HISTORY.map(([k]) => `<td class="num">${hours(sumOf(lines, k))}</td>`).join('');
const LEGEND = `<dl class="legend muted">
    <dt>Logged</dt><dd>all hours logged on the task</dd>
    <dt>Billed</dt><dd>invoiced or approved earlier</dd>
    <dt>Not billable</dt><dd>written off earlier, not charged</dd>
    <dt>Not billed</dt><dd>not invoiced yet</dd>
    <dt>To approve</dt><dd>the hours we ask you to approve now</dd>
  </dl>`;

// `values` optionally overrides what the inputs show (used to keep the customer's typed input after a validation error).
function reviewPage(review, lines, message, values) {
  const prefillStored = values ? true : hasStoredAnswer(lines);
  const approvedOf = l => {
    if (values && values[l.systemId]) return values[l.systemId].approved;
    return prefillStored ? Number(l.approvedHours) : requestedOf(l);
  };
  const commentOf = l => (values && values[l.systemId]) ? values[l.systemId].comment : (l.customerComment || '');
  const rows = lines.map(l => `
    <tr>
      <td><div class="task">${esc(l.taskNo)}</div><div class="desc">${esc(l.taskDescription)}</div>
          <input type="text" name="comment_${esc(l.systemId)}" placeholder="Comment (optional)" maxlength="250" value="${esc(commentOf(l))}" style="margin-top:6px">
          <input type="hidden" name="etag_${esc(l.systemId)}" value="${esc(l['@odata.etag'] || '')}"></td>
      ${historyCells(l)}
      <td class="num ask">${hours(requestedOf(l))}</td>
      <td class="num"><input type="number" name="approved_${esc(l.systemId)}" min="0" max="${requestedOf(l)}" step="0.01"
          value="${esc(approvedOf(l))}" data-requested="${requestedOf(l)}" required aria-label="Hours you approve for ${esc(l.taskNo)}"></td>
    </tr>`).join('');
  const totalRequested = lines.reduce((s, l) => s + requestedOf(l), 0);
  const totalApproved = lines.reduce((s, l) => s + (Number(approvedOf(l)) || 0), 0);
  const reopenedNotice = (!values && prefillStored)
    ? '<div class="notice">This review was reopened. Your previous answer is filled in below; adjust it and submit again.</div>' : '';
  return layout(`${cfg.brand}: ${review.projectNo}`, `
    <h1>${esc(cfg.brand)}</h1>
    <p class="muted">${esc(review.customerName)} &middot; ${esc(review.projectDescription || review.projectNo)} &middot; review #${esc(review.reviewNo)}</p>
    <div class="notice">We ask you to approve <strong>${hours(totalRequested)} hours</strong> for this project, shown per task in the
       highlighted <strong>To approve</strong> column. Confirm them in <strong>Your approval</strong>: keep the number to approve it,
       lower it to approve part of it, or set 0. The other columns show the task's history for reference.</div>
    ${reopenedNotice}
    ${message ? `<div class="notice warn">${esc(message)}</div>` : ''}
    <form method="post" action="/review/${esc(review.accessToken)}">
      <div class="scroll"><table>
        <thead><tr><th>Task</th>${historyHeads}<th class="num ask">To approve</th><th class="num">Your approval</th></tr></thead>
        <tbody>${rows}</tbody>
        <tfoot><tr><td>Total hours</td>${historyTotals(lines)}<td class="num ask">${hours(totalRequested)}</td><td class="num" id="total-approved">${hours(totalApproved)}</td></tr></tfoot>
      </table></div>
      ${LEGEND}
      <div class="actions">
        <button type="submit">Submit answer</button>
        <button type="button" class="secondary" id="approve-all">Approve all requested hours</button>
        <button type="button" class="secondary" id="reject-all">Set all to 0</button>
      </div>
    </form>
    <script>
      const inputs = [...document.querySelectorAll('input[type=number]')];
      const total = document.getElementById('total-approved');
      const fmt = n => n.toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      const recalc = () => total.textContent = fmt(inputs.reduce((s, i) => s + (Number(i.value) || 0), 0));
      inputs.forEach(i => i.addEventListener('input', recalc));
      document.getElementById('approve-all').onclick = () => { inputs.forEach(i => i.value = i.dataset.requested); recalc(); };
      document.getElementById('reject-all').onclick = () => { inputs.forEach(i => i.value = 0); recalc(); };
    </script>`);
}

function messagePage(title, text, kind) {
  return layout(`${cfg.brand}`, `<h1>${esc(cfg.brand)}</h1><div class="notice ${kind || ''}">${esc(text)}</div>`);
}

function answeredPage(review, lines) {
  const rows = lines.map(l => `<tr><td><div class="task">${esc(l.taskNo)}</div><div class="desc">${esc(l.taskDescription)}</div>${l.customerComment ? `<div class="desc muted">${esc(l.customerComment)}</div>` : ''}</td>
    ${historyCells(l)}<td class="num ask">${hours(requestedOf(l))}</td><td class="num">${hours(l.approvedHours)}</td></tr>`).join('');
  const answeredOn = review.answeredOn && !review.answeredOn.startsWith('0001-') ? new Date(review.answeredOn).toLocaleDateString('en-GB') : '';
  return layout(`${cfg.brand}: ${review.projectNo}`, `
    <h1>${esc(cfg.brand)}</h1>
    <p class="muted">${esc(review.customerName)} &middot; ${esc(review.projectDescription || review.projectNo)} &middot; review #${esc(review.reviewNo)}</p>
    <div class="notice ok">Thank you, your answer has been recorded${answeredOn ? ` on ${esc(answeredOn)}` : ''}.</div>
    <div class="scroll"><table>
      <thead><tr><th>Task</th>${historyHeads}<th class="num ask">To approve</th><th class="num">You approved</th></tr></thead>
      <tbody>${rows}</tbody>
      <tfoot><tr><td>Total hours</td>${historyTotals(lines)}<td class="num ask">${hours(lines.reduce((s, l) => s + requestedOf(l), 0))}</td><td class="num">${hours(sumOf(lines, 'approvedHours'))}</td></tr></tfoot>
    </table></div>
    ${LEGEND}`);
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

const NOT_VALID = 'This review link is not valid.';

async function handleGet(res, token) {
  const review = await findReview(token);
  if (!review) return send(res, 404, messagePage('Not found', NOT_VALID, 'warn'));
  const lines = await getLines(review.reviewNo);
  if (isAnswered(review)) return send(res, 200, answeredPage(review, lines));
  if (!isSent(review)) return send(res, 410, messagePage('Cancelled', 'This review has been cancelled. Please contact us if you have questions.', 'warn'));
  return send(res, 200, reviewPage(review, lines, null));
}

async function handlePost(req, res, token) {
  const review = await findReview(token);
  if (!review) return send(res, 404, messagePage('Not found', NOT_VALID, 'warn'));
  const lines = await getLines(review.reviewNo);
  if (isAnswered(review)) return send(res, 409, answeredPage(review, lines));
  if (!isSent(review)) return send(res, 410, messagePage('Cancelled', 'This review has been cancelled. Please contact us if you have questions.', 'warn'));

  const form = new URLSearchParams(await readBody(req));
  const values = {};
  const updates = [];
  let problem = null;
  for (const line of lines) {
    const raw = form.get(`approved_${line.systemId}`);
    const comment = (form.get(`comment_${line.systemId}`) || '').slice(0, 250);
    const etag = form.get(`etag_${line.systemId}`) || '*';
    values[line.systemId] = { approved: raw ?? '', comment };
    const requested = requestedOf(line);
    const approved = Number(String(raw ?? '').replace(',', '.'));
    if (raw === null || raw === '' || !Number.isFinite(approved) || approved < 0 || round2(approved) > requested) {
      problem = problem || `Approved hours for ${line.taskNo} must be between 0 and ${hours(requested)}.`;
      continue;
    }
    // Round to what BC stores and never exceed the requested hours after rounding.
    updates.push({ line, approved: Math.min(round2(approved), requested), comment, etag });
  }
  if (problem) return send(res, 400, reviewPage(review, lines, problem, values));

  try {
    for (const u of updates) {
      await bc('PATCH', `customerReviewLines(${u.line.systemId})`, { approvedHours: u.approved, customerComment: u.comment }, u.etag);
    }
    await bc('POST', `customerReviews(${review.systemId})/Microsoft.NAV.submit`, {});
  } catch (e) {
    console.error(`submit failed for review ${review.reviewNo}:`, e.status, e.code, e.message);
    const fresh = await findReview(token);
    const freshLines = await getLines(review.reviewNo);
    if (fresh && isAnswered(fresh)) return send(res, 200, answeredPage(fresh, freshLines));
    if (e.status === 412) {
      return send(res, 409, reviewPage(fresh || review, freshLines, 'This review was changed in the meantime, for example in another browser tab. The current values are shown below; please check them and submit again.'));
    }
    return send(res, 502, reviewPage(fresh || review, freshLines, 'Your answer could not be saved. Please try again, or contact us if the problem persists.', values));
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
    if (!TOKEN_RE.test(token)) return send(res, 404, messagePage('Not found', NOT_VALID, 'warn'));
    if (req.method === 'GET') return await handleGet(res, token);
    if (req.method === 'POST') return await handlePost(req, res, token);
    res.writeHead(405); res.end();
  } catch (e) {
    console.error(e);
    send(res, 500, messagePage('Error', 'Something went wrong on our side. Please try again later.', 'warn'));
  }
});

server.listen(cfg.port, () => console.log(`review-web listening on :${cfg.port} -> ${cfg.environment}`));
