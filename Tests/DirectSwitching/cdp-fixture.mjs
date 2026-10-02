// An isolated CDP-shaped test server. It has no connection to a desktop app.
import http from 'node:http';
import { createHash } from 'node:crypto';
const mode = process.argv[2] ?? 'success';
const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  const port = server.address().port;
  res.end(JSON.stringify([{ type: 'page', url: 'app://-/index.html',
    webSocketDebuggerUrl: `ws://${mode === 'remote' ? '192.0.2.1' : '127.0.0.1'}:${port}/devtools/page/test` }]));
});
function frame(value, opcode = 1) {
  const data = Buffer.from(value);
  const header = data.length < 126 ? Buffer.from([0x80 | opcode, data.length]) : Buffer.from([0x80 | opcode, 126, data.length >> 8, data.length & 255]);
  return Buffer.concat([header, data]);
}
server.on('upgrade', (req, socket) => {
  const key = createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${key}\r\n\r\n`);
  let pending = Buffer.alloc(0);
  socket.on('data', data => {
    pending = Buffer.concat([pending, data]);
    while (pending.length >= 2) {
      let size = pending[1] & 127, offset = 2;
      if (size === 126) { if (pending.length < 4) return; size = pending.readUInt16BE(2); offset = 4; }
      if (size === 127) { if (pending.length < 10) return; size = Number(pending.readBigUInt64BE(2)); offset = 10; }
      const masked = Boolean(pending[1] & 128);
      if (pending.length < offset + (masked ? 4 : 0) + size) return;
      const opcode = pending[0] & 15;
      const mask = masked ? pending.subarray(offset, offset + 4) : null;
      if (masked) offset += 4;
      const body = Buffer.from(pending.subarray(offset, offset + size));
      if (mask) for (let i = 0; i < body.length; i++) body[i] ^= mask[i % 4];
      pending = pending.subarray(offset + size);
      if (opcode === 8) { socket.end(frame(body, 8)); return; }
      if (opcode !== 1 || mode === 'stall') continue;
      const message = JSON.parse(body.toString());
      const preset = JSON.parse(message.params.expression.match(/applyCodexPreset\((\{[^}]+\})\)/)[1]);
      const slugs = { 'GPT-6 Astra': 'gpt-6-astra', 'GPT-6.1 Sol': 'gpt-6.1-sol' };
      socket.write(frame(JSON.stringify({ method: 'Runtime.consoleAPICalled', params: {} })));
      let result;
      if (mode === 'exception') result = { exceptionDetails: { exception: { description: 'Server rejected model settings' } } };
      else if (mode === 'exception-stack') result = { exceptionDetails: { exception: { description: '\n  Error: Open one active Codex chat.\n    at locate (<anonymous>:30:31)\n    at applyCodexPreset (<anonymous>:56:19)' } } };
      else if (mode === 'mismatch') result = { result: { value: { model: 'unexpected-model', displayName: 'Unexpected model', effort: preset.effort, changed: true } } };
      else if (mode === 'effort-mismatch') result = { result: { value: { model: slugs[preset.model] ?? preset.model, displayName: preset.model, effort: preset.effort === 'high' ? 'xhigh' : 'high', changed: true } } };
      else if (mode === 'alias') result = { result: { value: { model: 'provider:special-v2', displayName: 'My Custom Model', effort: 'xhigh', changed: true } } };
      else {
        result = { result: { value: { model: slugs[preset.model] ?? preset.model, displayName: preset.model, effort: preset.effort, changed: true } } };
      }
      socket.write(frame(JSON.stringify({ id: message.id, result })));
    }
  });
  socket.on('error', () => {});
});
server.listen(0, '127.0.0.1', () => process.stdout.write(String(server.address().port) + '\n'));
