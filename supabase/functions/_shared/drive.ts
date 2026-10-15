// Helpers do Google Drive (Edge Functions `drive` e `gmail-callback` com provider drive).
// Mesma regra do Gmail: nunca registrar tokens, nomes de arquivos nem corpo de resposta do Google.
import { classify, type FetchFn, GoogleError, HTTP_TIMEOUT_MS, readJson, request } from "./gmail.ts";

export const DRIVE_API = "https://www.googleapis.com/drive/v3";
export const DRIVE_UPLOAD_API = "https://www.googleapis.com/upload/drive/v3";
export const FOLDER_MIME = "application/vnd.google-apps.folder";
export const ROOT_FOLDER_NAME = "Organize";
/** Tetos de itens por consulta: acima disso a resposta vem cortada, com `truncated: true`. */
export const LIST_LIMIT = 1000;
export const SEARCH_LIMIT = 200;
export const PERMISSIONS_LIMIT = 200;
/** Máximo de itens que o Drive aceita por página em files.list e em permissions.list. */
const FILES_PAGE_MAX = 1000;
const PERMISSIONS_PAGE_MAX = 100;
/** Host aceito na URL de upload devolvida pelo Google. */
export const UPLOAD_HOST = "www.googleapis.com";
export const FILE_FIELDS = "id,name,mimeType,size,modifiedTime,webViewLink,iconLink,shared,parents";

// ---------------------------------------------------------------- armazenamento

export interface DriveAccountRow {
  user_id: string;
  account_email: string;
  refresh_token_enc: string;
  scopes: string;
}

export interface DriveStateRow {
  status: "not_connected" | "ok" | "auth_required" | "error";
  root_folder_id: string | null;
  account_email?: string | null;
}

export interface DriveStatePatch {
  account_email?: string | null;
  status?: "not_connected" | "ok" | "auth_required" | "error";
  root_folder_id?: string | null;
  message?: string | null;
  connected_at?: string | null;
}

export interface DriveStore {
  getAccount(userId: string): Promise<DriveAccountRow | null>;
  upsertAccount(row: DriveAccountRow): Promise<void>;
  deleteAccount(userId: string): Promise<void>;
  /** Existe outra linha de google_accounts do usuário (outro provider) com o mesmo account_email? */
  hasSiblingAccount(userId: string, accountEmail: string): Promise<boolean>;
  getState(userId: string): Promise<DriveStateRow | null>;
  setState(userId: string, patch: DriveStatePatch): Promise<void>;
}

// ---------------------------------------------------------------- itens

export interface DriveItem {
  id: string;
  name: string;
  mimeType: string;
  isFolder: boolean;
  size: number | null;
  modifiedTime: string | null;
  webViewLink: string | null;
  iconLink: string | null;
  shared: boolean;
}

export interface DriveFolder {
  id: string;
  name: string;
  parents: string[];
}

/** IDs do Drive são [A-Za-z0-9_-]; "root" é o alias do Meu Drive. Nada além disso entra numa consulta. */
export const validId = (v: unknown): v is string => typeof v === "string" && /^[A-Za-z0-9_-]{1,200}$/.test(v);

/** Escapa o valor de uma consulta `q` do Drive (aspas simples e barras). */
export const qEscape = (s: string): string => s.replace(/\\/g, "\\\\").replace(/'/g, "\\'");

export function toItem(f: Record<string, unknown>): DriveItem {
  const mimeType = typeof f.mimeType === "string" ? f.mimeType : "";
  const size = typeof f.size === "string" && /^\d+$/.test(f.size) ? Number(f.size) : typeof f.size === "number" ? f.size : null;
  return {
    id: String(f.id ?? ""),
    name: typeof f.name === "string" ? f.name : "",
    mimeType,
    isFolder: mimeType === FOLDER_MIME,
    size,
    modifiedTime: typeof f.modifiedTime === "string" ? f.modifiedTime : null,
    webViewLink: typeof f.webViewLink === "string" ? f.webViewLink : null,
    iconLink: typeof f.iconLink === "string" ? f.iconLink : null,
    shared: f.shared === true,
  };
}

export const authz = (accessToken: string) => ({ Authorization: `Bearer ${accessToken}` });
const jsonHeaders = (accessToken: string) => ({ ...authz(accessToken), "Content-Type": "application/json" });

// ---------------------------------------------------------------- chamadas

/**
 * Como `request`, mas um 403 (sem permissão naquele arquivo) NÃO é tratado como "token inválido":
 * vira "other"/403, para o app mostrar o motivo sem pedir reconexão. 401 continua sendo auth.
 */
export async function driveRequest(
  fetchFn: FetchFn,
  url: string,
  init: RequestInit = {},
  allow404 = false,
): Promise<Record<string, unknown> | null> {
  try {
    return await request(fetchFn, url, init, false, allow404);
  } catch (e) {
    if (e instanceof GoogleError && e.kind === "auth" && e.status === 403) throw new GoogleError("other", 403);
    throw e;
  }
}

export const driveJson = (accessToken: string, method: string, body?: unknown): RequestInit => ({
  method,
  headers: body === undefined ? authz(accessToken) : jsonHeaders(accessToken),
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
});

export async function getAboutEmail(accessToken: string, fetchFn: FetchFn): Promise<string> {
  const j = await driveRequest(fetchFn, `${DRIVE_API}/about?fields=user(emailAddress)`, { headers: authz(accessToken) });
  const email = (j?.user as { emailAddress?: unknown } | undefined)?.emailAddress;
  if (typeof email !== "string" || !email) throw new GoogleError("other");
  return email;
}

/**
 * Pagina uma coleção do Drive (`files` ou `permissions`) com nextPageToken até [cap] itens.
 * `truncated` = havia mais itens além do teto. [baseParams] não leva pageSize/pageToken.
 */
export async function listPaged(
  fetchFn: FetchFn,
  url: string,
  baseParams: Record<string, string>,
  key: "files" | "permissions",
  accessToken: string,
  cap: number,
  pageMax: number,
): Promise<{ rows: Record<string, unknown>[]; truncated: boolean }> {
  const rows: Record<string, unknown>[] = [];
  let pageToken: string | undefined;
  for (let guard = 0; guard < 50; guard++) {
    const p = new URLSearchParams({ ...baseParams, pageSize: String(Math.min(cap - rows.length, pageMax)) });
    if (pageToken) p.set("pageToken", pageToken);
    const j = await driveRequest(fetchFn, `${url}?${p}`, { headers: authz(accessToken) });
    const page = Array.isArray(j?.[key]) ? j![key] as Record<string, unknown>[] : [];
    rows.push(...page);
    const next = typeof j?.nextPageToken === "string" && j.nextPageToken ? j.nextPageToken : undefined;
    if (!next) return { rows, truncated: false };
    if (rows.length >= cap) return { rows: rows.slice(0, cap), truncated: true };
    pageToken = next;
  }
  return { rows, truncated: true };
}

/** Lista as pastas/arquivos de [parentId] (sem lixeira): pastas primeiro, nome ascendente. Até [limit] itens. */
export async function listChildren(
  accessToken: string,
  parentId: string,
  fetchFn: FetchFn,
  limit = LIST_LIMIT,
): Promise<{ items: DriveItem[]; truncated: boolean }> {
  const { rows, truncated } = await listPaged(
    fetchFn,
    `${DRIVE_API}/files`,
    {
      q: `'${qEscape(parentId)}' in parents and trashed = false`,
      orderBy: "folder,name",
      fields: `nextPageToken,files(${FILE_FIELDS})`,
    },
    "files",
    accessToken,
    limit,
    FILES_PAGE_MAX,
  );
  return { items: rows.map(toItem), truncated };
}

/** Busca por nome (sem lixeira). Até [limit] itens. */
export async function searchFiles(
  accessToken: string,
  text: string,
  fetchFn: FetchFn,
  limit = SEARCH_LIMIT,
): Promise<{ items: DriveItem[]; truncated: boolean }> {
  const { rows, truncated } = await listPaged(
    fetchFn,
    `${DRIVE_API}/files`,
    {
      q: `name contains '${qEscape(text)}' and trashed = false`,
      orderBy: "folder,name",
      fields: `nextPageToken,files(${FILE_FIELDS})`,
    },
    "files",
    accessToken,
    limit,
    FILES_PAGE_MAX,
  );
  return { items: rows.map(toItem), truncated };
}

export async function getFolder(accessToken: string, id: string, fetchFn: FetchFn): Promise<DriveFolder> {
  const j = await driveRequest(fetchFn, `${DRIVE_API}/files/${encodeURIComponent(id)}?fields=id,name,parents`, {
    headers: authz(accessToken),
  });
  if (!j || typeof j.id !== "string") throw new GoogleError("other");
  return {
    id: j.id,
    name: typeof j.name === "string" ? j.name : "",
    parents: Array.isArray(j.parents) ? j.parents.filter((x): x is string => typeof x === "string") : [],
  };
}

export async function createFolder(accessToken: string, parentId: string, name: string, fetchFn: FetchFn): Promise<DriveItem> {
  const j = await driveRequest(fetchFn, `${DRIVE_API}/files?fields=${FILE_FIELDS}`, {
    method: "POST",
    headers: jsonHeaders(accessToken),
    body: JSON.stringify({ name, mimeType: FOLDER_MIME, parents: [parentId] }),
  });
  if (!j || typeof j.id !== "string") throw new GoogleError("other");
  return toItem(j);
}

/** Acha a pasta [name] (fora da lixeira) em [parentId] ou cria. */
export async function ensureFolder(accessToken: string, parentId: string, name: string, fetchFn: FetchFn): Promise<DriveItem> {
  const p = new URLSearchParams({
    q: `'${qEscape(parentId)}' in parents and name = '${qEscape(name)}' and mimeType = '${FOLDER_MIME}' and trashed = false`,
    pageSize: "1",
    fields: `files(${FILE_FIELDS})`,
  });
  const j = await driveRequest(fetchFn, `${DRIVE_API}/files?${p}`, { headers: authz(accessToken) });
  const found = Array.isArray(j?.files) ? (j!.files as Record<string, unknown>[])[0] : undefined;
  if (found && typeof found.id === "string") return toItem(found);
  return await createFolder(accessToken, parentId, name, fetchFn);
}

/** sha256 em hexadecimal minúsculo (64 caracteres): a chave de deduplicação dos arquivos importados. */
export const validSha256 = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f]{64}$/.test(v);

export interface FoundFile {
  id: string;
  name: string;
  webViewLink: string | null;
}

/** Acha, fora da lixeira, um arquivo cujo appProperties.sha256 é [sha256] (gravado no upload). */
export async function findBySha256(accessToken: string, sha256: string, fetchFn: FetchFn): Promise<FoundFile | null> {
  if (!validSha256(sha256)) throw new GoogleError("other"); // nunca entra na consulta sem validar
  const p = new URLSearchParams({
    q: `appProperties has { key='sha256' and value='${sha256}' } and trashed = false`,
    pageSize: "1",
    fields: "files(id,name,webViewLink)",
  });
  const j = await driveRequest(fetchFn, `${DRIVE_API}/files?${p}`, { headers: authz(accessToken) });
  const f = Array.isArray(j?.files) ? (j!.files as Record<string, unknown>[])[0] : undefined;
  if (!f || typeof f.id !== "string") return null;
  return {
    id: f.id,
    name: typeof f.name === "string" ? f.name : "",
    webViewLink: typeof f.webViewLink === "string" ? f.webViewLink : null,
  };
}

/**
 * Cria uma sessão de upload resumable e devolve a URL (Location). O app envia o arquivo
 * direto para essa URL, sem token. A resposta final do PUT traz id, name e webViewLink.
 */
export async function createUploadSession(
  accessToken: string,
  meta: { parentId: string; name: string; mimeType: string; size: number; appProperties?: Record<string, string> },
  fetchFn: FetchFn,
): Promise<string> {
  let res: Response;
  try {
    res = await fetchFn(`${DRIVE_UPLOAD_API}/files?uploadType=resumable&fields=id,name,webViewLink`, {
      method: "POST",
      headers: {
        ...jsonHeaders(accessToken),
        "X-Upload-Content-Type": meta.mimeType,
        "X-Upload-Content-Length": String(meta.size),
      },
      body: JSON.stringify({
        name: meta.name,
        parents: [meta.parentId],
        mimeType: meta.mimeType,
        ...(meta.appProperties ? { appProperties: meta.appProperties } : {}),
      }),
      signal: AbortSignal.timeout(HTTP_TIMEOUT_MS),
    });
  } catch {
    throw new GoogleError("transient");
  }
  if (!res.ok) {
    const err = classify(res.status, await readJson(res), false);
    throw err.kind === "auth" && err.status === 403 ? new GoogleError("other", 403) : err;
  }
  await res.body?.cancel().catch(() => {});
  const location = res.headers.get("location") ?? "";
  let url: URL;
  try {
    url = new URL(location);
  } catch {
    throw new GoogleError("other");
  }
  if (url.protocol !== "https:" || url.hostname !== UPLOAD_HOST || url.username || url.password || url.port) {
    throw new GoogleError("other");
  }
  return url.toString();
}

// ---------------------------------------------------------------- download

/** Teto de um download pelo servidor (o app grava o arquivo inteiro no aparelho). */
export const MAX_DOWNLOAD_BYTES = 50 * 1024 * 1024;

export interface DownloadMeta {
  name: string;
  mimeType: string;
  size: number | null;
}

export async function getDownloadMeta(accessToken: string, id: string, fetchFn: FetchFn): Promise<DownloadMeta> {
  const j = await driveRequest(fetchFn, `${DRIVE_API}/files/${encodeURIComponent(id)}?fields=id,name,mimeType,size`, {
    headers: authz(accessToken),
  });
  if (!j || typeof j.id !== "string") throw new GoogleError("other");
  const item = toItem(j);
  return { name: item.name, mimeType: item.mimeType, size: item.size };
}

export interface FileMeta {
  id: string;
  name: string;
  mimeType: string;
  size: number | null;
  modifiedTime: string | null;
  /** Só arquivos binários têm md5 (Docs/Sheets nativos não). */
  md5Checksum: string | null;
  webViewLink: string | null;
}

/**
 * Metadados que o app compara com o cache local para decidir se baixa de novo.
 * Arquivo na lixeira conta como inexistente (404), igual ao Drive para quem não o vê mais.
 */
export async function getFileMeta(accessToken: string, id: string, fetchFn: FetchFn): Promise<FileMeta> {
  const j = await driveRequest(
    fetchFn,
    `${DRIVE_API}/files/${encodeURIComponent(id)}?fields=id,name,mimeType,size,modifiedTime,md5Checksum,webViewLink,trashed`,
    { headers: authz(accessToken) },
  );
  if (!j || typeof j.id !== "string") throw new GoogleError("other");
  if (j.trashed === true) throw new GoogleError("other", 404);
  const item = toItem(j);
  return {
    id: item.id,
    name: item.name,
    mimeType: item.mimeType,
    size: item.size,
    modifiedTime: item.modifiedTime,
    md5Checksum: typeof j.md5Checksum === "string" && /^[0-9a-f]{32}$/i.test(j.md5Checksum) ? j.md5Checksum.toLowerCase() : null,
    webViewLink: item.webViewLink,
  };
}

/**
 * Abre `files/{id}?alt=media` e devolve a resposta (corpo ainda não lido) para repassar em streaming.
 * O prazo de [HTTP_TIMEOUT_MS] vale só até os cabeçalhos chegarem; depois o corpo flui sem corte.
 */
export async function openMedia(accessToken: string, id: string, fetchFn: FetchFn): Promise<Response> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), HTTP_TIMEOUT_MS);
  let res: Response;
  try {
    res = await fetchFn(`${DRIVE_API}/files/${encodeURIComponent(id)}?alt=media`, { headers: authz(accessToken), signal: ctl.signal });
  } catch {
    throw new GoogleError("transient");
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) {
    const err = classify(res.status, await readJson(res), false);
    throw err.kind === "auth" && err.status === 403 ? new GoogleError("other", 403) : err;
  }
  if (!res.body) throw new GoogleError("other");
  return res;
}

/**
 * Cabeçalho Content-Disposition seguro: sem aspas, barras, quebras de linha ou controles no nome ASCII,
 * e o nome original em `filename*` (RFC 5987) com percent-encoding.
 */
export function contentDisposition(name: string): string {
  // deno-lint-ignore no-control-regex
  const clean = name.replace(/[\u0000-\u001f\u007f]/g, "").trim() || "arquivo";
  const ascii = clean.replace(/[^\x20-\x7e]|["\\\/;]/g, "_");
  const star = encodeURIComponent(clean).replace(/['()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
  return `attachment; filename="${ascii}"; filename*=UTF-8''${star}`;
}
