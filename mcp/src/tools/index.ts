import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { SupabaseClient } from '@supabase/supabase-js';
import { registerAgenda } from './agenda.js';
import { registerAlexa, type AlexaOptions } from './alexa.js';
import { registerFitness } from './fitness.js';
import { registerNews } from './news.js';
import { registerNotes } from './notes.js';
import { registerNotices } from './notices.js';
import { registerShopping } from './shopping.js';
import { registerStudy } from './study.js';
import { registerTasks } from './tasks.js';
import { registerWake } from './wake.js';

export interface ToolContext {
  db: SupabaseClient;
  userId: string;
  timeZone: string;
  now: () => Date;
}

export interface ToolOptions {
  alexa?: AlexaOptions;
}

/** Como `registerTools`, com opções (usadas nos testes para encurtar a espera da ponte). */
export function registerAllTools(server: McpServer, ctx: ToolContext, opts: ToolOptions = {}): void {
  registerAgenda(server, ctx);
  registerTasks(server, ctx);
  registerNotes(server, ctx);
  registerStudy(server, ctx);
  registerNotices(server, ctx);
  registerNews(server, ctx);
  registerAlexa(server, ctx, opts.alexa);
  registerWake(server, ctx);
  registerShopping(server, ctx);
  registerFitness(server, ctx);
}

/** Registra todas as ferramentas no servidor MCP. */
export function registerTools(server: McpServer, ctx: ToolContext): void {
  registerAllTools(server, ctx);
}
