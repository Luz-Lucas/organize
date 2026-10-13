// Helpers do Google Drive (Edge Functions `drive` e `gmail-callback` com provider drive).
// Mesma regra do Gmail: nunca registrar tokens, nomes de arquivos nem corpo de resposta do Google.
import { classify, type FetchFn, GoogleError, HTTP_TIMEOUT_MS, readJson, request } from "./gmail.ts";

export const DRIVE_API = "https://www.googleapis.com/drive/v3";
export const DRIVE_UPLOAD_API = "https://www.googleapis.com/upload/drive/v3";
export const FOLDER_MIME = "application/vnd.google-apps.folder";
export const ROOT_FOLDER_NAME = "Organizacional";
export const LIST_LIMIT = 200;
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

/** Lista as pastas/arquivos de [parentId] (sem lixeira): pastas primeiro, nome ascendente. */
export async function listChildren(
  accessToken: string,
  parentId: string,
  fetchFn: FetchFn,
  limit = LIST_LIMIT,
): Promise<DriveItem[]> {
  const p = new URLSearchParams({
    q: `'${qEscape(parentId)}' in parents and trashed = false`,
    orderBy: "folder,name",
    pageSize: String(limit),
    fields: `files(${FILE_FIELDS})`,
  });
  const j = await driveRequest(fetchFn, `${DRIVE_API}/files?${p}`, { headers: authz(accessToken) });
  const files = Array.isArray(j?.files) ? j!.files as Record<string, unknown>[] : [];
  return files.map(toItem);
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

/**
 * Cria uma sessão de upload resumable e devolve a URL (Location). O app envia o arquivo
 * direto para essa URL, sem token. A resposta final do PUT traz id, name e webViewLink.
 */
export async function createUploadSession(
  accessToken: string,
  meta: { parentId: string; name: string; mimeType: string; size: number },
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
      body: JSON.stringify({ name: meta.name, parents: [meta.parentId], mimeType: meta.mimeType }),
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
  if (url.protocol !== "https:" || !url.hostname.endsWith("googleapis.com")) throw new GoogleError("other");
  return url.toString();
}
