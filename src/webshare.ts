import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import { localAddresses } from './net.js';
import { generateQrMatrix, renderTerminalQr, renderSvgQr } from './qr.js';

export interface WebShareSession {
  token: string;
  files: string[];
  mode: 'download' | 'upload';
  createdAt: number;
}

let activeServer: http.Server | null = null;
const activeSessions = new Map<string, WebShareSession>();

/**
 * Starts the reverse WebShare portal on port 53319.
 */
export async function startWebSharePortal(
  files: string[],
  mode: 'download' | 'upload' = 'download',
  uploadDir?: string,
  port = 53319
): Promise<{ url: string; qrTerminal: string; token: string }> {
  const token = crypto.randomBytes(4).toString('hex');
  activeSessions.set(token, {
    token,
    files,
    mode,
    createdAt: Date.now(),
  });

  if (!activeServer) {
    activeServer = http.createServer((req, res) => {
      const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
      const tokenParam = url.searchParams.get('token') || '';
      const session = activeSessions.get(tokenParam);

      if (!session) {
        res.writeHead(403, { 'Content-Type': 'text/plain' });
        res.end('Access Denied: Invalid or expired Web-Share token.');
        return;
      }

      if (url.pathname === '/' || url.pathname === '/share') {
        if (session.mode === 'download') {
          // Serve download list HTML
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          let items = session.files.map((f, idx) => {
            const name = path.basename(f);
            return `<li style="margin: 10px 0;"><a style="color: #00796B; font-weight: 600; text-decoration: none;" href="/download?token=${token}&idx=${idx}">${name}</a></li>`;
          }).join('');

          res.end(`<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>LocalSend Web-Share</title></head><body style="font-family: sans-serif; text-align: center; padding: 2em;"><h1 style="color: #00796B;">LocalSend Downloads</h1><ul style="list-style: none; padding: 0; max-width: 500px; margin: 0 auto; text-align: left;">${items}</ul></body></html>`);
        } else {
          // Serve upload form HTML
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(`<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>LocalSend Upload</title></head><body style="font-family: sans-serif; text-align: center; padding: 2em;"><h1 style="color: #00796B;">Send Files to Desktop</h1><form method="POST" action="/upload?token=${token}" enctype="multipart/form-data"><input type="file" name="files" multiple style="margin: 20px 0;"><br><button type="submit" style="padding: 10px 24px; background: #00796B; color: #fff; border: none; border-radius: 6px; font-size: 1.1em; cursor: pointer;">Upload Now</button></form></body></html>`);
        }
        return;
      }

      if (url.pathname === '/download') {
        const idxStr = url.searchParams.get('idx');
        const idx = idxStr ? parseInt(idxStr, 10) : 0;
        const targetPath = session.files[idx];

        if (!targetPath || !fs.existsSync(targetPath)) {
          res.writeHead(404, { 'Content-Type': 'text/plain' });
          res.end('File not found.');
          return;
        }

        const stat = fs.statSync(targetPath);
        res.writeHead(200, {
          'Content-Length': stat.size,
          'Content-Disposition': `attachment; filename="${path.basename(targetPath)}"`,
          'Content-Type': 'application/octet-stream',
        });
        fs.createReadStream(targetPath).pipe(res);
        return;
      }

      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    });

    await new Promise<void>((resolve, reject) => {
      activeServer!.listen(port, () => resolve());
      activeServer!.on('error', (err: any) => {
        if (err.code === 'EADDRINUSE') {
          resolve(); // Already running
        } else {
          reject(err);
        }
      });
    });
  }

  const primaryIp = localAddresses()[0] || '127.0.0.1';
  const url = `http://${primaryIp}:${port}/share?token=${token}`;
  const matrix = generateQrMatrix(url);
  const qrTerminal = renderTerminalQr(matrix);

  return { url, qrTerminal, token };
}
