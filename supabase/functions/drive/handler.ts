import {
  bearer,
  CORS,
  decryptToken,
  type FetchFn,
  type GmailConfig,
  GoogleError,
  json,
  refreshAccessToken,
  revokeToken,
  validEmail,
} from "../_shared/gmail.ts";
import {
  authz,
  createFolder,
  createUploadSession,
  DRIVE_API,
  driveJson,
  driveRequest,
  type DriveStore,
  ensureFolder,
  FILE_FIELDS,
  getFolder,
  listChildren,
  qEscape,
  toItem,
  validId,
} from "../_shared/drive.ts";

export interface TokenEntry {
  token: string;
  exp: number;
}

export interface DriveDeps {
  cfg: GmailConfig | null;
  store: DriveStore;
  fetchFn: FetchFn;
  getUserId: (jwt: string) => Promise<string | null>;
  /** Cache em memória do access token por usuário (vale até expirar). */
  tokenCache?: Map<string, TokenEntry>;
  now?: () => number;
}

const TOKEN_TTL_MS = 50 * 60 * 1000; // o Google emite 60 min
const SEARCH_LIMIT = 100;
const defaultCache = new Map<string, TokenEntry>();

const MSG_AUTH = "O acesso ao Google Drive expirou. Reconecte em Ajustes.";
const MSG_NOT_CONNECTED = "Google Drive não conectado. Conecte em Ajustes.";
const MSG_UNAVAILABLE = "O Google Drive está indisponível agora. Tente de novo em instantes.";

/** Erro de entrada: vira 400 com a mensagem (sempre texto fixo nosso). */
class BadRequest extends Error {}
class NotConnected extends Error {}

const ROLES = ["reader", "writer", "commenter"] as const;
type Role = typeof ROLES[number];
const MIME_RE = /^[A-Za-z0-9][\w.+-]*\/[\w.+*-]+$/;

type Body = Record<string, unknown>;

function id(v: unknown, what = "item"): string {
  if (!validId(v)) throw new BadRequest(`Identificador de ${what} inválido.`);
  return v;
}

function name(v: unknown): string {
  const s = typeof v === "string" ? v.trim() : "";
  if (s.length < 1 || s.length > 255) throw new BadRequest("O nome deve ter de 1 a 255 caracteres.");
  return s;
}

function failure(status: number, error: string, code?: string): Response {
  return json({ error, ...(code ? { code } : {}) }, status);
}

/** POST { action, ... } com o JWT do usuário. Respostas em JSON; erros em pt-BR sem detalhes do Google. */
export async function handle(req: Request, deps: DriveDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "método não permitido" }, 405);
  const cfg = deps.cfg;
  if (!cfg) return json({ error: "serviço não configurado" }, 500);

  const jwt = bearer(req);
  const userId = jwt ? await deps.getUserId(jwt).catch(() => null) : null;
  if (!userId) return json({ error: "não autorizado" }, 401);

  const body = await req.json().catch(() => ({})) as Body;
  const action = typeof body?.action === "string" ? body.action : "";
  const cache = deps.tokenCache ?? defaultCache;
  const now = deps.now ?? Date.now;
  const { store, fetchFn } = deps;

  const markAuthRequired = async () => {
    cache.delete(userId);
    try {
      await store.setState(userId, { status: "auth_required", message: MSG_AUTH });
    } catch {
      console.error("drive: não gravou o estado");
    }
  };

  async function accessToken(force: boolean): Promise<string> {
    const hit = cache.get(userId!);
    if (!force && hit && hit.exp > now()) return hit.token;
    const acct = await store.getAccount(userId!);
    if (!acct) throw new NotConnected();
    let refresh: string;
    try {
      refresh = await decryptToken(acct.refresh_token_enc, cfg!.tokenKey);
    } catch {
      throw new GoogleError("auth"); // chave trocada: só reconectando
    }
    const token = await refreshAccessToken(cfg!, refresh, fetchFn);
    cache.set(userId!, { token, exp: now() + TOKEN_TTL_MS });
    return token;
  }

  /** Executa [fn] com o token; num 401 renova o token uma vez e repete. */
  async function withToken<T>(fn: (token: string) => Promise<T>): Promise<T> {
    const token = await accessToken(false);
    try {
      return await fn(token);
    } catch (e) {
      if (e instanceof GoogleError && e.kind === "auth") return await fn(await accessToken(true));
      throw e;
    }
  }

  try {
    switch (action) {
      case "disconnect": {
        const acct = await store.getAccount(userId);
        if (acct && cfg) {
          try {
            await revokeToken(await decryptToken(acct.refresh_token_enc, cfg.tokenKey), fetchFn);
          } catch {
            // melhor esforço: apagar os dados locais é o que importa
          }
        }
        await store.deleteAccount(userId);
        await store.setState(userId, {
          status: "not_connected",
          account_email: null,
          root_folder_id: null,
          message: null,
          connected_at: null,
        });
        cache.delete(userId);
        return json({ ok: true });
      }

      case "list": {
        const raw = body.folderId;
        let folderId: string;
        if (raw === undefined || raw === null) {
          const st = await store.getState(userId);
          folderId = st?.root_folder_id && validId(st.root_folder_id) ? st.root_folder_id : "root";
        } else {
          folderId = id(raw, "pasta");
        }
        const out = await withToken(async (t) => {
          const [folder, items] = await Promise.all([getFolder(t, folderId, fetchFn), listChildren(t, folderId, fetchFn)]);
          return { folder, items };
        });
        return json(out);
      }

      case "search": {
        const q = typeof body.q === "string" ? body.q.trim() : "";
        if (q.length < 1 || q.length > 200) throw new BadRequest("Digite o que procurar (até 200 caracteres).");
        const items = await withToken(async (t) => {
          const p = new URLSearchParams({
            q: `name contains '${qEscape(q)}' and trashed = false`,
            orderBy: "folder,name",
            pageSize: String(SEARCH_LIMIT),
            fields: `files(${FILE_FIELDS})`,
          });
          const j = await driveRequest(fetchFn, `${DRIVE_API}/files?${p}`, { headers: authz(t) });
          const files = Array.isArray(j?.files) ? j!.files as Record<string, unknown>[] : [];
          return files.map(toItem);
        });
        return json({ items });
      }

      case "create_folder": {
        const parentId = id(body.parentId, "pasta");
        const n = name(body.name);
        const item = await withToken((t) => createFolder(t, parentId, n, fetchFn));
        return json({ item });
      }

      case "ensure_folder": {
        const parentId = id(body.parentId, "pasta");
        const n = name(body.name);
        const item = await withToken((t) => ensureFolder(t, parentId, n, fetchFn));
        return json({ item });
      }

      case "rename": {
        const fid = id(body.id);
        const n = name(body.name);
        await withToken((t) =>
          driveRequest(fetchFn, `${DRIVE_API}/files/${fid}?fields=id`, driveJson(t, "PATCH", { name: n }))
        );
        return json({ ok: true });
      }

      case "trash":
      case "restore": {
        const fid = id(body.id);
        await withToken((t) =>
          driveRequest(fetchFn, `${DRIVE_API}/files/${fid}?fields=id`, driveJson(t, "PATCH", { trashed: action === "trash" }))
        );
        return json({ ok: true });
      }

      case "move": {
        const fid = id(body.id);
        const to = id(body.toFolderId, "pasta");
        await withToken(async (t) => {
          const cur = await driveRequest(fetchFn, `${DRIVE_API}/files/${fid}?fields=parents`, { headers: authz(t) });
          const parents = Array.isArray(cur?.parents) ? cur!.parents.filter((x): x is string => typeof x === "string") : [];
          const p = new URLSearchParams({ addParents: to, fields: "id" });
          if (parents.length) p.set("removeParents", parents.join(","));
          await driveRequest(fetchFn, `${DRIVE_API}/files/${fid}?${p}`, driveJson(t, "PATCH", {}));
        });
        return json({ ok: true });
      }

      case "share": {
        const fid = id(body.id);
        const email = body.email;
        if (!validEmail(email)) throw new BadRequest("E-mail inválido.");
        const role = body.role as Role;
        if (!ROLES.includes(role)) throw new BadRequest("Papel inválido.");
        const notify = body.notify === true;
        await withToken((t) =>
          driveRequest(
            fetchFn,
            `${DRIVE_API}/files/${fid}/permissions?sendNotificationEmail=${notify}&fields=id`,
            driveJson(t, "POST", { type: "user", role, emailAddress: email }),
          )
        );
        return json({ ok: true });
      }

      case "share_link": {
        const fid = id(body.id);
        if (typeof body.enabled !== "boolean") throw new BadRequest("Informe se o link deve ficar ligado.");
        const enabled = body.enabled;
        const webViewLink = await withToken(async (t) => {
          if (enabled) {
            await driveRequest(fetchFn, `${DRIVE_API}/files/${fid}/permissions?fields=id`, driveJson(t, "POST", { type: "anyone", role: "reader" }));
          } else {
            const list = await listPermissions(t, fid);
            for (const perm of list.filter((x) => x.type === "anyone")) {
              await driveRequest(fetchFn, `${DRIVE_API}/files/${fid}/permissions/${perm.id}`, { method: "DELETE", headers: authz(t) });
            }
          }
          const f = await driveRequest(fetchFn, `${DRIVE_API}/files/${fid}?fields=webViewLink`, { headers: authz(t) });
          return typeof f?.webViewLink === "string" ? f.webViewLink : null;
        });
        return json({ webViewLink });
      }

      case "permissions": {
        const fid = id(body.id);
        return json({ permissions: await withToken((t) => listPermissions(t, fid)) });
      }

      case "unshare": {
        const fid = id(body.id);
        const pid = id(body.permissionId, "permissão");
        await withToken((t) =>
          driveRequest(fetchFn, `${DRIVE_API}/files/${fid}/permissions/${pid}`, { method: "DELETE", headers: authz(t) })
        );
        return json({ ok: true });
      }

      case "upload_session": {
        const parentId = id(body.parentId, "pasta");
        const n = name(body.name);
        const mimeType = typeof body.mimeType === "string" ? body.mimeType.trim() : "";
        if (!MIME_RE.test(mimeType) || mimeType.length > 200) throw new BadRequest("Tipo de arquivo inválido.");
        const size = body.size;
        if (typeof size !== "number" || !Number.isInteger(size) || size < 0 || size > 5 * 1024 ** 4) {
          throw new BadRequest("Tamanho de arquivo inválido.");
        }
        const uploadUrl = await withToken((t) => createUploadSession(t, { parentId, name: n, mimeType, size }, fetchFn));
        return json({ uploadUrl });
      }

      default:
        throw new BadRequest("Ação desconhecida.");
    }
  } catch (e) {
    if (e instanceof BadRequest) return failure(400, e.message);
    if (e instanceof NotConnected) return failure(409, MSG_NOT_CONNECTED, "not_connected");
    if (e instanceof GoogleError) {
      // Só o tipo do erro vai para o log: nada de nomes de arquivos, e-mails ou tokens.
      console.error("drive: falha", e.message);
      if (e.kind === "auth") {
        await markAuthRequired();
        return failure(409, MSG_AUTH, "auth_required");
      }
      if (e.kind === "transient") return failure(502, MSG_UNAVAILABLE, "unavailable");
      if (e.status === 404) return failure(404, "Item não encontrado no Google Drive.", "not_found");
      if (e.status === 403) return failure(403, "Sem permissão para fazer isso no Google Drive.", "forbidden");
      if (e.status >= 400 && e.status < 500) return failure(400, "O Google Drive não aceitou a operação.", "rejected");
      return failure(502, MSG_UNAVAILABLE, "unavailable");
    }
    console.error("drive: falha interna", e instanceof Error ? e.message : "?");
    return failure(500, "Erro interno.");
  }

  async function listPermissions(t: string, fid: string) {
    const p = new URLSearchParams({ fields: "permissions(id,emailAddress,role,type)", pageSize: "100" });
    const j = await driveRequest(fetchFn, `${DRIVE_API}/files/${fid}/permissions?${p}`, { headers: authz(t) });
    const list = Array.isArray(j?.permissions) ? j!.permissions as Record<string, unknown>[] : [];
    return list
      .filter((x) => typeof x.id === "string")
      .map((x) => ({
        id: x.id as string,
        email: typeof x.emailAddress === "string" ? x.emailAddress : null,
        role: typeof x.role === "string" ? x.role : "reader",
        type: typeof x.type === "string" ? x.type : "user",
      }));
  }
}
