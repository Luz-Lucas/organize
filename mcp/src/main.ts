import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { createClient } from '@supabase/supabase-js';
import { loadConfig } from './config.js';
import { buildApp } from './http.js';
import { registerTools, type ToolContext } from './tools/index.js';

const cfg = loadConfig(process.env);
const log = (m: string) => console.log(`[${new Date().toISOString()}] ${m}`);

process.on('unhandledRejection', (reason) => log(`rejeição não tratada: ${String((reason as Error)?.message ?? 'erro')}`));

const ctx: ToolContext = {
  db: createClient(cfg.supabaseUrl, cfg.serviceKey, { auth: { persistSession: false } }),
  userId: cfg.userId,
  timeZone: cfg.timeZone,
  now: () => new Date(),
};

const app = buildApp(cfg, {
  makeServer: () => {
    const server = new McpServer({ name: 'organizacional', version: '1.0.0' });
    registerTools(server, ctx);
    return server;
  },
});

app.listen(cfg.port, () => log(`MCP ouvindo na porta ${cfg.port}`));
