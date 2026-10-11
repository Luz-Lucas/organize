import { randomBytes } from 'node:crypto';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { registerAllTools, type ToolOptions } from '../src/tools/index.js';

export const SUPABASE_URL = process.env.SUPABASE_URL;
export const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
export const hasDb = !!SUPABASE_URL && !!SERVICE_KEY;

export function serviceClient(): SupabaseClient {
  return createClient(SUPABASE_URL!, SERVICE_KEY!, { auth: { persistSession: false, autoRefreshToken: false } });
}

/** Cria um usuário descartável no Auth local (apagar no afterAll; a cascata limpa os dados). */
export async function createTestUser(db: SupabaseClient, tag: string): Promise<string> {
  const email = `mcp-${tag}-${randomBytes(4).toString('hex')}@teste.local`;
  const { data, error } = await db.auth.admin.createUser({
    email, password: randomBytes(12).toString('hex'), email_confirm: true,
  });
  if (error || !data.user) throw new Error(`falha ao criar usuário de teste: ${error?.message}`);
  return data.user.id;
}

export async function deleteTestUser(db: SupabaseClient, id: string): Promise<void> {
  await db.auth.admin.deleteUser(id);
}

export interface Connected {
  client: Client;
  close: () => Promise<void>;
}

export async function connectTools(
  db: SupabaseClient, userId: string, opts: { now?: () => Date; tools?: ToolOptions; timeZone?: string } = {},
): Promise<Connected> {
  const server = new McpServer({ name: 'organizacional-test', version: '0.0.0' });
  registerAllTools(server, {
    db, userId, timeZone: opts.timeZone ?? 'America/Sao_Paulo', now: opts.now ?? (() => new Date()),
  }, opts.tools);
  const [ct, st] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: 'test', version: '0.0.0' });
  await Promise.all([server.connect(st), client.connect(ct)]);
  return { client, close: async () => { await client.close(); await server.close(); } };
}

export interface CallResult {
  isError: boolean;
  text: string;
  data: any; // eslint-disable-line @typescript-eslint/no-explicit-any
}

export async function call(client: Client, name: string, args: Record<string, unknown> = {}): Promise<CallResult> {
  try {
    const res = await client.callTool({ name, arguments: args });
    const text = (res.content as { type: string; text: string }[]).map((c) => c.text).join('\n');
    let data: unknown = null;
    try { data = JSON.parse(text); } catch { /* mensagem de erro em texto */ }
    return { isError: !!res.isError, text, data };
  } catch (e) {
    // Argumentos inválidos podem sair como erro de protocolo (InvalidParams).
    return { isError: true, text: (e as Error).message, data: null };
  }
}
