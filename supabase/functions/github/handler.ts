import { bearer, CORS, json } from "../_shared/gmail.ts";

export interface GithubDeps {
  /** Token fine-grained (segredo GITHUB_TOKEN). null = não configurado. */
  token: string | null;
  /** Único usuário do Supabase autorizado (GITHUB_ALLOWED_USER_ID). null = não configurado. */
  allowedUserId: string | null;
  /** Repositórios permitidos (GITHUB_REPOS). Vazio = os que o token enxerga. */
  repos: string[];
  getUserId: (jwt: string) => Promise<string | null>;
  fetch: typeof fetch;
}

const API = "https://api.github.com";
const REPO_RE = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const MAX_TITLE = 256;
const MAX_BODY = 65536;
const MAX_LABELS = 20;
const MAX_LABEL = 50;
const LIST_LIMIT = 30;

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const bad = (message: string) => new HttpError(400, message);

type Obj = Record<string, unknown>;

function ghHeaders(token: string): Record<string, string> {
  return {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "organizacional",
    Authorization: `Bearer ${token}`,
  };
}

/** Chama o GitHub; erros viram HttpError em pt-BR (sem repassar corpo nem token). */
async function gh(d: GithubDeps, method: string, path: string, body?: unknown): Promise<unknown> {
  let res: Response;
  try {
    res = await d.fetch(`${API}${path}`, {
      method,
      headers: { ...ghHeaders(d.token!), ...(body === undefined ? {} : { "Content-Type": "application/json" }) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new HttpError(502, "Não foi possível falar com o GitHub.");
  }
  if (!res.ok) {
    await res.body?.cancel();
    switch (res.status) {
      case 401:
        throw new HttpError(502, "Token do GitHub inválido ou expirado.");
      case 403:
      case 429:
        throw new HttpError(502, "O GitHub recusou: falta permissão do token ou o limite de requisições foi atingido.");
      case 404:
        throw new HttpError(404, "Repositório ou issue não encontrado (confira as permissões do token).");
      case 422:
        throw new HttpError(422, "O GitHub recusou os dados enviados.");
      default:
        throw new HttpError(502, `Falha ao falar com o GitHub (${res.status}).`);
    }
  }
  try {
    return await res.json();
  } catch {
    throw new HttpError(502, "Resposta inesperada do GitHub.");
  }
}

const asArray = (v: unknown): Obj[] => (Array.isArray(v) ? (v as Obj[]) : []);

const REPOS_PER_PAGE = 100;
const REPOS_MAX_PAGES = 10;

/** Repositórios do token, paginados (100 por página) até vir uma página curta, com teto de 10 páginas. */
async function listUserRepos(d: GithubDeps): Promise<Obj[]> {
  const all: Obj[] = [];
  for (let page = 1; page <= REPOS_MAX_PAGES; page++) {
    const rows = asArray(await gh(d, "GET", `/user/repos?per_page=${REPOS_PER_PAGE}&sort=pushed&page=${page}`));
    all.push(...rows);
    if (rows.length < REPOS_PER_PAGE) break;
  }
  return all;
}

async function allowedRepos(d: GithubDeps): Promise<string[]> {
  if (d.repos.length) return d.repos;
  return (await listUserRepos(d)).map((r) => r.full_name).filter((n): n is string => typeof n === "string");
}

/** Valida o repo contra a lista permitida e devolve o nome canônico da lista. */
async function resolveRepo(d: GithubDeps, input: unknown): Promise<string> {
  if (typeof input !== "string" || !REPO_RE.test(input)) throw bad("Repositório inválido.");
  const found = (await allowedRepos(d)).find((r) => r.toLowerCase() === input.toLowerCase());
  if (!found || !REPO_RE.test(found)) throw new HttpError(403, "Repositório não permitido.");
  return found;
}

function issueNumber(v: unknown): number {
  if (typeof v !== "number" || !Number.isSafeInteger(v) || v < 1) throw bad("Número da issue inválido.");
  return v;
}

function text(v: unknown, what: string, max: number, required: boolean): string | undefined {
  if (v === undefined || v === null) {
    if (required) throw bad(`${what} é obrigatório.`);
    return undefined;
  }
  if (typeof v !== "string") throw bad(`${what} inválido.`);
  const t = v.trim();
  if (required && !t) throw bad(`${what} é obrigatório.`);
  if (t.length > max) throw bad(`${what} muito longo (máximo ${max} caracteres).`);
  return t;
}

function labelNames(v: unknown): string[] {
  return asArray(v).map((l) => (typeof l === "string" ? l : (l as Obj)?.name)).filter((n): n is string => typeof n === "string");
}

async function run(d: GithubDeps, b: Obj): Promise<unknown> {
  switch (b.action) {
    case "repos": {
      if (!d.repos.length) {
        const rows = await listUserRepos(d);
        return rows.filter((r) => typeof r.full_name === "string").map((r) => ({ fullName: r.full_name, private: r.private === true }));
      }
      return await Promise.all(d.repos.map(async (name) => {
        try {
          const r = (await gh(d, "GET", `/repos/${name}`)) as Obj;
          return { fullName: typeof r.full_name === "string" ? r.full_name : name, private: r.private === true };
        } catch {
          return { fullName: name, private: true }; // sem acesso: mostra, tratando como privado
        }
      }));
    }
    case "list": {
      const state = b.state ?? "open";
      if (state !== "open" && state !== "closed" && state !== "all") throw bad("Estado inválido.");
      const repo = await resolveRepo(d, b.repo);
      const rows = asArray(await gh(d, "GET", `/repos/${repo}/issues?state=${state}&per_page=100&sort=created&direction=desc`));
      return rows
        .filter((i) => i.pull_request === undefined || i.pull_request === null)
        .slice(0, LIST_LIMIT)
        .map((i) => ({
          number: i.number,
          title: i.title,
          state: i.state,
          labels: labelNames(i.labels),
          createdAt: i.created_at,
          url: i.html_url,
          comments: typeof i.comments === "number" ? i.comments : 0,
        }));
    }
    case "create": {
      const title = text(b.title, "Título", MAX_TITLE, true)!;
      const body = text(b.body, "Descrição", MAX_BODY, false);
      let labels: string[] | undefined;
      if (b.labels !== undefined && b.labels !== null) {
        if (!Array.isArray(b.labels) || b.labels.length > MAX_LABELS || b.labels.some((l) => typeof l !== "string" || !l.trim() || l.length > MAX_LABEL)) {
          throw bad("Rótulos inválidos.");
        }
        labels = b.labels as string[];
      }
      const repo = await resolveRepo(d, b.repo);
      const payload: Obj = { title };
      if (body) payload.body = body;
      if (labels?.length) payload.labels = labels;
      const r = (await gh(d, "POST", `/repos/${repo}/issues`, payload)) as Obj;
      return { number: r.number, url: r.html_url };
    }
    case "set_state": {
      const n = issueNumber(b.number);
      if (b.state !== "open" && b.state !== "closed") throw bad("Estado inválido.");
      const repo = await resolveRepo(d, b.repo);
      await gh(d, "PATCH", `/repos/${repo}/issues/${n}`, { state: b.state });
      return { ok: true };
    }
    case "comment": {
      const n = issueNumber(b.number);
      const body = text(b.body, "Comentário", MAX_BODY, true)!;
      const repo = await resolveRepo(d, b.repo);
      await gh(d, "POST", `/repos/${repo}/issues/${n}/comments`, { body });
      return { ok: true };
    }
    case "labels": {
      const repo = await resolveRepo(d, b.repo);
      return labelNames(await gh(d, "GET", `/repos/${repo}/labels?per_page=100`));
    }
    default:
      throw bad("Ação desconhecida.");
  }
}

/** POST { action, ... } -> JSON. Só o dono (GITHUB_ALLOWED_USER_ID), identificado pelo JWT do Supabase. */
export async function handle(req: Request, deps: GithubDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "método não permitido" }, 405);
  if (!deps.token || !deps.allowedUserId) return json({ error: "GitHub não configurado" }, 500);

  const jwt = bearer(req);
  const userId = jwt ? await deps.getUserId(jwt).catch(() => null) : null;
  if (!userId) return json({ error: "não autorizado" }, 401);
  if (userId !== deps.allowedUserId) return json({ error: "acesso negado" }, 403);

  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "corpo inválido" }, 400);

  try {
    return json(await run(deps, body as Obj));
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    return json({ error: "Falha inesperada ao falar com o GitHub." }, 500);
  }
}
