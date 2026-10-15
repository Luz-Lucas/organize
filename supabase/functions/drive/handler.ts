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
  contentDisposition,
  findBySha256,
  getDownloadMeta,
  getFileMeta,
  getFolder,
  listChildren,
  listPaged,
  MAX_DOWNLOAD_BYTES,
  openMedia,
  PERMISSIONS_LIMIT,
  searchFiles,
  validId,
  validSha256,
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
const defaultCache = new Map<string, TokenEntry>();

const MSG_AUTH = "O acesso ao Google Drive expirou. Reconecte em Ajustes.";
const MSG_NOT_CONNECTED = "Google Drive não conectado. Conecte em Ajustes.";
const MSG_UNAVAILABLE = "O Google Drive está indisponível agora. Tente de novo em instantes.";

/** Erro de entrada: vira 400 com a mensagem (sempre texto fixo nosso). */
class BadRequest extends Error {}
class NotConnected extends Error {}
class TooLarge extends Error {}

const ROLES = ["reader", "writer", "commenter"] as const;
type Role = typeof ROLES[number];
const MIME_RE = /^[A-Za-z0-9][\w.+-]*\/[\w.+-]+$/; // sem "*": curinga não é tipo de arquivo
const GOOGLE_NATIVE_MIME_PREFIX = "application/vnd.google-apps."; // Docs/Sheets/pasta: o upload não cria isso

type Body = Record<string, unknown>;

async function sha256Hex(text: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return [...d].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function id(v: unknown, what = "item"): string {
  if (!validId(v)) throw new BadRequest(`Identificador de ${what} inválido.`);
  return v;
}

function name(v: unknown): string {
  const s = typeof v === "string" ? v.trim() : "";
  if (s.length < 1 || s.length > 255) throw new BadRequest("O nome deve ter de 1 a 255 caracteres.");
  return s;
}

const MAX_PATH_DEPTH = 5;

/** Nome de UMA pasta de um caminho: sem separadores, sem caracteres de controle, nem "." / "..". */
function pathSegment(v: unknown): string {
  const s = typeof v === "string" ? v.trim() : "";
  // deno-lint-ignore no-control-regex
  if (s.length < 1 || s.length > 255 || /[\/\\\u0000-\u001f\u007f]/.test(s) || s === "." || s === "..") {
    throw new BadRequest("Nome de pasta inválido.");
  }
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

  /** Esquece todos os access tokens em cache deste usuário (a chave leva o hash do refresh token). */
  const dropCached = () => {
    for (const k of [...cache.keys()]) if (k.startsWith(`${userId}:`)) cache.delete(k);
  };

  const markAuthRequired = async () => {
    dropCached();
    try {
      await store.setState(userId, { status: "auth_required", message: MSG_AUTH });
    } catch {
      console.error("drive: não gravou o estado");
    }
  };

  async function accessToken(force: boolean): Promise<string> {
    const acct = await store.getAccount(userId!);
    if (!acct) throw new NotConnected();
    // A chave depende do refresh token gravado: reconectar (token novo) nunca reaproveita o access token antigo.
    const cacheKey = `${userId}:${await sha256Hex(acct.refresh_token_enc)}`;
    const hit = cache.get(cacheKey);
    if (!force && hit && hit.exp > now()) return hit.token;
    let refresh: string;
    try {
      refresh = await decryptToken(acct.refresh_token_enc, cfg!.tokenKey);
    } catch {
      throw new GoogleError("auth"); // chave trocada: só reconectando
    }
    const token = await refreshAccessToken(cfg!, refresh, fetchFn);
    dropCached(); // só um access token por usuário: os de refresh tokens anteriores saem
    cache.set(cacheKey, { token, exp: now() + TOKEN_TTL_MS });
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
          // Gmail e Drive usam o mesmo client OAuth: revogar aqui derrubaria também o Gmail da mesma conta Google.
          const shared = await store.hasSiblingAccount(userId, acct.account_email).catch(() => true);
          if (!shared) {
            try {
              await revokeToken(await decryptToken(acct.refresh_token_enc, cfg.tokenKey), fetchFn);
            } catch {
              // melhor esforço: apagar os dados locais é o que importa
            }
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
        dropCached();
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
          const [folder, listing] = await Promise.all([getFolder(t, folderId, fetchFn), listChildren(t, folderId, fetchFn)]);
          return { folder, items: listing.items, truncated: listing.truncated };
        });
        return json(out);
      }

      case "search": {
        const q = typeof body.q === "string" ? body.q.trim() : "";
        if (q.length < 1 || q.length > 200) throw new BadRequest("Digite o que procurar (até 200 caracteres).");
        const found = await withToken((t) => searchFiles(t, q, fetchFn));
        return json({ items: found.items, truncated: found.truncated });
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
          const already = parents.includes(to);
          const leaving = parents.filter((x) => x !== to); // o destino nunca sai dos pais
          if (already && leaving.length === 0) return; // já está só nessa pasta: nada a fazer
          const p = new URLSearchParams({ fields: "id" });
          if (!already) p.set("addParents", to);
          if (leaving.length) p.set("removeParents", leaving.join(","));
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
            for (const perm of list.permissions.filter((x) => x.type === "anyone")) {
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
        const out = await withToken((t) => listPermissions(t, fid));
        return json({ permissions: out.permissions, truncated: out.truncated });
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
        if (!MIME_RE.test(mimeType) || mimeType.length > 200 || mimeType.toLowerCase().startsWith(GOOGLE_NATIVE_MIME_PREFIX)) {
          throw new BadRequest("Tipo de arquivo inválido.");
        }
        const size = body.size;
        if (typeof size !== "number" || !Number.isInteger(size) || size < 0 || size > 5 * 1024 ** 4) {
          throw new BadRequest("Tamanho de arquivo inválido.");
        }
        // Opcional (o app antigo não manda): só {sha256} em hex minúsculo; null conta como ausente.
        let appProperties: { sha256: string } | undefined;
        const ap = body.appProperties;
        if (ap !== undefined && ap !== null) {
          const keys = ap && typeof ap === "object" && !Array.isArray(ap) ? Object.keys(ap) : [];
          if (keys.length !== 1 || keys[0] !== "sha256" || !validSha256((ap as Body).sha256)) {
            throw new BadRequest("Propriedades do arquivo inválidas.");
          }
          appProperties = { sha256: (ap as { sha256: string }).sha256 };
        }
        const uploadUrl = await withToken((t) =>
          createUploadSession(t, { parentId, name: n, mimeType, size, ...(appProperties ? { appProperties } : {}) }, fetchFn)
        );
        return json({ uploadUrl });
      }

      case "ensure_path": {
        const raw = body.path;
        if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_PATH_DEPTH) {
          throw new BadRequest(`Informe o caminho com 1 a ${MAX_PATH_DEPTH} pastas.`);
        }
        const names = raw.map(pathSegment);
        const folderId = await withToken(async (t) => {
          let parent = "root";
          for (const n of names) parent = (await ensureFolder(t, parent, n, fetchFn)).id;
          return parent;
        });
        return json({ folderId });
      }

      case "find_by_sha256": {
        const sha = body.sha256;
        if (!validSha256(sha)) throw new BadRequest("Hash do arquivo inválido.");
        const file = await withToken((t) => findBySha256(t, sha, fetchFn));
        return json({ file });
      }

      case "meta": {
        const fid = id(body.id, "arquivo");
        const file = await withToken((t) => getFileMeta(t, fid, fetchFn));
        return json({ file });
      }

      case "download": {
        const fid = id(body.id, "arquivo");
        const out = await withToken(async (t) => {
          const meta = await getDownloadMeta(t, fid, fetchFn);
          if (meta.mimeType.toLowerCase().startsWith(GOOGLE_NATIVE_MIME_PREFIX) || meta.size === null) {
            throw new BadRequest("Este tipo de arquivo não pode ser baixado. Abra no Google Drive.");
          }
          if (meta.size > MAX_DOWNLOAD_BYTES) throw new TooLarge();
          return { meta, res: await openMedia(t, fid, fetchFn) };
        });
        return new Response(out.res.body, {
          status: 200,
          headers: {
            "Content-Type": "application/octet-stream",
            "Content-Disposition": contentDisposition(out.meta.name),
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            ...CORS,
          },
        });
      }

      default:
        throw new BadRequest("Ação desconhecida.");
    }
  } catch (e) {
    if (e instanceof BadRequest) return failure(400, e.message);
    if (e instanceof TooLarge) return failure(413, "O arquivo é grande demais para baixar pelo app (máximo de 50 MB). Abra no Google Drive.", "too_large");
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
    const { rows, truncated } = await listPaged(
      fetchFn,
      `${DRIVE_API}/files/${fid}/permissions`,
      { fields: "nextPageToken,permissions(id,emailAddress,role,type)" },
      "permissions",
      t,
      PERMISSIONS_LIMIT,
      100,
    );
    const permissions = rows
      .filter((x) => typeof x.id === "string")
      .map((x) => ({
        id: x.id as string,
        email: typeof x.emailAddress === "string" ? x.emailAddress : null,
        role: typeof x.role === "string" ? x.role : "reader",
        type: typeof x.type === "string" ? x.type : "user",
      }));
    return { permissions, truncated };
  }
}
