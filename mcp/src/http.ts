import express, { type NextFunction, type Request, type Response } from 'express';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import type { McpConfig } from './config.js';
import { createOAuthRouter } from './oauth/router.js';
import { OAuthStore } from './oauth/store.js';
import { verifyAccessToken } from './oauth/tokens.js';

export const ALLOWED_ORIGINS = ['https://claude.ai', 'https://claude.com'];

const CORS_PATHS = /^\/(mcp(\/.*)?|\.well-known\/.*|register|token|revoke)$/;

export interface HttpDeps {
  makeServer: () => McpServer;
  now?: () => Date;
  /** Limite de POST /register por IP por hora (padrão 20; testes elevam). */
  registerPerHour?: number;
}

export function buildApp(cfg: McpConfig, deps: HttpDeps): express.Express {
  const now = deps.now ?? (() => new Date());
  const store = new OAuthStore(cfg.dataDir, now);
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);

  app.use((_req, res, next) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    next();
  });

  // CORS estrito: só claude.ai/claude.com.
  app.use((req, res, next) => {
    const origin = req.headers.origin;
    const allowed = typeof origin === 'string' && ALLOWED_ORIGINS.includes(origin);
    if (CORS_PATHS.test(req.path)) {
      res.append('Vary', 'Origin');
      if (allowed) {
        res.setHeader('Access-Control-Allow-Origin', origin);
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type, Mcp-Session-Id, Mcp-Protocol-Version, Last-Event-ID');
        res.setHeader('Access-Control-Expose-Headers', 'WWW-Authenticate, Mcp-Session-Id');
        res.setHeader('Access-Control-Max-Age', '600');
      }
      if (req.method === 'OPTIONS') return void res.status(204).end();
    }
    // /mcp: origem de navegador não autorizada é recusada (proteção contra DNS rebinding).
    if (/^\/mcp(\/|$)/.test(req.path) && typeof origin === 'string' && !allowed) {
      return void res.status(403).json({ error: 'forbidden', error_description: 'Origem não permitida.' });
    }
    next();
  });

  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: false, limit: '64kb' }));

  app.use(createOAuthRouter(cfg, store, now, { registerPerHour: deps.registerPerHour }));

  const metadataUrl = `${cfg.publicUrl}/.well-known/oauth-protected-resource`;
  const unauthorized = (res: Response, hadToken: boolean) => {
    res.setHeader('WWW-Authenticate',
      `Bearer ${hadToken ? 'error="invalid_token", ' : ''}resource_metadata="${metadataUrl}"`);
    res.status(401).json({ error: hadToken ? 'invalid_token' : 'unauthorized' });
  };

  const requireAuth = async (req: Request, res: Response, next: NextFunction) => {
    const m = /^Bearer ([A-Za-z0-9\-._~+/]+=*)$/i.exec(req.headers.authorization ?? '');
    if (!m || !(await verifyAccessToken(cfg, m[1], now()))) return unauthorized(res, Boolean(m));
    next();
  };

  const methodNotAllowed = (_req: Request, res: Response) => {
    res.setHeader('Allow', 'POST');
    res.status(405).json({ jsonrpc: '2.0', error: { code: -32000, message: 'Método não permitido.' }, id: null });
  };

  // Modo sem sessão: um servidor + um transporte por requisição.
  app.post('/mcp', requireAuth, async (req, res) => {
    const server = deps.makeServer();
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    res.on('close', () => {
      void transport.close();
      void server.close();
    });
    try {
      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
    } catch {
      if (!res.headersSent) {
        res.status(500).json({ jsonrpc: '2.0', error: { code: -32603, message: 'Erro interno.' }, id: null });
      }
    }
  });
  app.get('/mcp', requireAuth, methodNotAllowed);
  app.delete('/mcp', requireAuth, methodNotAllowed);

  // Erros (ex.: JSON inválido): sem stack, sem corpo da requisição nos logs.
  app.use((err: { status?: number; type?: string }, _req: Request, res: Response, _next: NextFunction) => {
    const status = err.status && err.status >= 400 && err.status < 500 ? err.status : 500;
    res.setHeader('Cache-Control', 'no-store');
    res.status(status).json({ error: status === 500 ? 'server_error' : 'invalid_request' });
  });

  return app;
}
