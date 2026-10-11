import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { SupabaseClient } from '@supabase/supabase-js';

export interface ToolContext {
  db: SupabaseClient;
  userId: string;
  timeZone: string;
  now: () => Date;
}

/** Registra todas as ferramentas no servidor MCP. (Implementada pela Task 2.) */
export function registerTools(_server: McpServer, _ctx: ToolContext): void {}
