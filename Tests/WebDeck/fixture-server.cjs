// Isolated UI fixture. This never connects to Codex or the native companion.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const resources = path.resolve(__dirname, '../../Sources/CodexUsageWeb/Resources');
const port = Number(process.env.DECK_FIXTURE_PORT || 8765);
const presets = [
  { slot: 1, model: 'gpt-6-astra', effort: 'ultra' },
  { slot: 2, model: 'gpt-6-astra', effort: 'xhigh' },
  { slot: 3, model: 'gpt-6-astra', effort: 'high' },
  { slot: 4, model: 'gpt-6.1-sol', effort: 'xhigh' },
  { slot: 5, model: 'gpt-6.1-sol', effort: 'high' }
];
let selection = { model: 'gpt-6.1-sol', effort: 'high' };
let scenario = 'ready';
const server = http.createServer(async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const json = (status, data, headers = {}) => {
    res.writeHead(status, { 'Content-Type': 'application/json', ...headers });
    res.end(JSON.stringify(data));
  };
  const pathname = new URL(req.url, 'http://127.0.0.1').pathname;
  if (pathname === '/fixture/scenario' && req.method === 'POST') {
    let input = ''; for await (const chunk of req) input += chunk;
    scenario = JSON.parse(input).scenario;
    return json(200, { ok: true });
  }
  if (pathname === '/api/pair') {
    let input = ''; for await (const chunk of req) input += chunk;
    if (JSON.parse(input).token !== 'fixture-token') return json(401, { error: 'Fixture pairing link expired.' });
    return json(200, { csrf: 'fixture-csrf' }, { 'Set-Cookie': 'deck-fixture=paired; HttpOnly; SameSite=Strict; Path=/' });
  }
  if (pathname.startsWith('/api/')) {
    if (!req.headers.cookie?.includes('deck-fixture=paired')) return json(401, { error: 'Pair this fixture browser.' });
    if (req.method === 'POST' && req.headers['x-deck-csrf'] !== 'fixture-csrf') return json(403, { error: 'Invalid fixture CSRF.' });
    if (pathname === '/api/state') {
      if (scenario === 'offline') { req.socket.destroy(); return; }
      return json(200, {
        csrf: 'fixture-csrf', connected: scenario !== 'unavailable', busy: scenario === 'busy',
        target: scenario === 'unavailable' ? null : { id: scenario === 'changed' ? 'fixture-chat-b' : 'fixture-chat-a', title: scenario === 'long' ? 'Fixture: a very long active chat title that should wrap cleanly on a narrow phone screen without hiding any controls' : 'Web remote · Fixture chat' },
        presets, usage: '93% remaining · reset in 6d 22h', selection,
        message: scenario === 'unavailable' ? 'Open a Codex chat and enable Direct Switching on your Mac.' : undefined
      });
    }
    if (pathname === '/api/preset') {
      let input = ''; for await (const chunk of req) input += chunk;
      const body = JSON.parse(input);
      if (scenario === 'stale') return json(409, { error: 'The active chat changed.' });
      const preset = presets.find(p => p.slot === body.slot && p.model === body.model && p.effort === body.effort);
      if (!preset) return json(409, { error: 'The preset changed.' });
      await new Promise(resolve => setTimeout(resolve, 250));
      selection = { model: preset.model, effort: preset.effort };
      return json(200, { ok: true, message: 'Preset applied to the fixture chat.' });
    }
    if (pathname === '/api/logout') return json(200, { ok: true }, { 'Set-Cookie': 'deck-fixture=; Max-Age=0; HttpOnly; SameSite=Strict; Path=/' });
    return json(404, { error: 'Unknown fixture route.' });
  }
  const files = { '/': ['index.html', 'text/html'], '/deck.css': ['deck.css', 'text/css'], '/deck.js': ['deck.js', 'text/javascript'] };
  const asset = files[pathname];
  if (!asset) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': asset[1] + '; charset=utf-8' });
  res.end(fs.readFileSync(path.join(resources, asset[0])));
});
server.listen(port, '127.0.0.1', () => {
  console.log(`UI fixture only: http://127.0.0.1:${port}/#pair=fixture-token`);
});
