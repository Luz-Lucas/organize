import { assert, assertEquals } from "jsr:@std/assert@1";
import { type GithubDeps, handle } from "./handler.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";
const TOKEN = "github_pat_SEGREDO_DE_TESTE";

const getUserId = (jwt: string) =>
  Promise.resolve(jwt === "jwt-dono" ? OWNER : jwt === "jwt-outro" ? OTHER : null);

interface Call {
  url: string;
  method: string;
  headers: Headers;
  body: unknown;
}

type Reply = { status?: number; body?: unknown } | Error;

/** fetch falso: responde pelo "MÉTODO url" (sem a origem) e registra as chamadas. */
function fakeFetch(routes: Record<string, Reply | ((c: Call) => Reply)>) {
  const calls: Call[] = [];
  const fn = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const call: Call = {
      url,
      method,
      headers: new Headers(init?.headers),
      body: typeof init?.body === "string" ? JSON.parse(init.body) : undefined,
    };
    calls.push(call);
    const key = `${method} ${url.replace("https://api.github.com", "")}`;
    const route = routes[key];
    if (route === undefined) return Promise.resolve(new Response(JSON.stringify({ message: "rota inesperada " + key }), { status: 599 }));
    const reply = typeof route === "function" ? route(call) : route;
    if (reply instanceof Error) return Promise.reject(reply);
    return Promise.resolve(
      new Response(JSON.stringify(reply.body ?? {}), {
        status: reply.status ?? 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  }) as typeof fetch;
  return { fn, calls };
}

function deps(over: Partial<GithubDeps> & { fetch: typeof fetch }): GithubDeps {
  return { token: TOKEN, allowedUserId: OWNER, repos: ["luz/app", "luz/outro"], getUserId, ...over };
}

const post = (body: unknown, jwt: string | null = "jwt-dono") =>
  new Request("https://x/functions/v1/github", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

const run = async (req: Request, d: GithubDeps) => {
  const res = await handle(req, d);
  const text = await res.text();
  return { status: res.status, json: text ? JSON.parse(text) : null, text };
};

Deno.test("sem JWT válido é 401; outro usuário é 403; GET é 405; OPTIONS é 204", async () => {
  const { fn, calls } = fakeFetch({});
  for (const jwt of [null, "jwt-ruim"]) {
    assertEquals((await run(post({ action: "repos" }, jwt), deps({ fetch: fn }))).status, 401);
  }
  const outro = await run(post({ action: "repos" }, "jwt-outro"), deps({ fetch: fn }));
  assertEquals(outro.status, 403);
  assertEquals(calls.length, 0);

  const get = await handle(new Request("https://x/", { method: "GET" }), deps({ fetch: fn }));
  assertEquals(get.status, 405);
  await get.body?.cancel();
  const opt = await handle(new Request("https://x/", { method: "OPTIONS" }), deps({ fetch: fn }));
  assertEquals(opt.status, 204);
  assertEquals(opt.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("sem GITHUB_TOKEN ou sem dono configurado é 500 'GitHub não configurado' (falha fechada)", async () => {
  const { fn, calls } = fakeFetch({});
  const semToken = await run(post({ action: "repos" }), deps({ fetch: fn, token: null }));
  assertEquals(semToken.status, 500);
  assertEquals(semToken.json.error, "GitHub não configurado");
  const semDono = await run(post({ action: "repos" }), deps({ fetch: fn, allowedUserId: null }));
  assertEquals(semDono.status, 500);
  assertEquals(calls.length, 0);
});

Deno.test("corpo inválido e ação desconhecida são 400", async () => {
  const { fn } = fakeFetch({});
  const req = new Request("https://x/", { method: "POST", headers: { Authorization: "Bearer jwt-dono" }, body: "{não é json" });
  assertEquals((await run(req, deps({ fetch: fn }))).status, 400);
  assertEquals((await run(post({ action: "apagar_tudo" }), deps({ fetch: fn }))).status, 400);
  assertEquals((await run(post({}), deps({ fetch: fn }))).status, 400);
});

Deno.test("repos com GITHUB_REPOS consulta cada repositório e devolve fullName/private", async () => {
  const { fn, calls } = fakeFetch({
    "GET /repos/luz/app": { body: { full_name: "luz/app", private: true } },
    "GET /repos/luz/outro": { body: { full_name: "luz/outro", private: false } },
  });
  const r = await run(post({ action: "repos" }), deps({ fetch: fn }));
  assertEquals(r.status, 200);
  assertEquals(r.json, [{ fullName: "luz/app", private: true }, { fullName: "luz/outro", private: false }]);
  // cabeçalhos exigidos pelo GitHub; o token vai só no Authorization, nunca na resposta
  const h = calls[0].headers;
  assertEquals(h.get("Accept"), "application/vnd.github+json");
  assertEquals(h.get("X-GitHub-Api-Version"), "2022-11-28");
  assertEquals(h.get("User-Agent"), "organizacional");
  assertEquals(h.get("Authorization"), `Bearer ${TOKEN}`);
  assert(!r.text.includes(TOKEN));
});

const REPOS = "/user/repos?per_page=100&sort=pushed&page=";
const page = (n: number, size: number) =>
  Array.from({ length: size }, (_, i) => ({ full_name: `luz/r${n}-${i}`, private: i % 2 === 0 }));

Deno.test("repos sem GITHUB_REPOS usa /user/repos paginado e para na página curta", async () => {
  const { fn, calls } = fakeFetch({
    [`GET ${REPOS}1`]: {
      body: [{ full_name: "luz/app", private: true }, { full_name: "org/publico", private: false }],
    },
  });
  const r = await run(post({ action: "repos" }), deps({ fetch: fn, repos: [] }));
  assertEquals(r.json, [{ fullName: "luz/app", private: true }, { fullName: "org/publico", private: false }]);
  assertEquals(calls.length, 1);
});

Deno.test("repos pagina até vir uma página com menos de 100 itens", async () => {
  const { fn, calls } = fakeFetch({
    [`GET ${REPOS}1`]: { body: page(1, 100) },
    [`GET ${REPOS}2`]: { body: page(2, 100) },
    [`GET ${REPOS}3`]: { body: page(3, 5) },
  });
  const r = await run(post({ action: "repos" }), deps({ fetch: fn, repos: [] }));
  assertEquals(r.status, 200);
  assertEquals(r.json.length, 205);
  assertEquals(r.json[100], { fullName: "luz/r2-0", private: true });
  assertEquals(calls.map((c) => c.url.split("&page=")[1]), ["1", "2", "3"]);
});

Deno.test("repos para no teto de 10 páginas mesmo que todas venham cheias", async () => {
  const routes: Record<string, Reply> = {};
  for (let n = 1; n <= 12; n++) routes[`GET ${REPOS}${n}`] = { body: page(n, 100) };
  const { fn, calls } = fakeFetch(routes);
  const r = await run(post({ action: "repos" }), deps({ fetch: fn, repos: [] }));
  assertEquals(r.status, 200);
  assertEquals(calls.length, 10);
  assertEquals(r.json.length, 1000);
});

Deno.test("a lista permitida (sem GITHUB_REPOS) inclui repositórios que só aparecem na página 2", async () => {
  const { fn, calls } = fakeFetch({
    [`GET ${REPOS}1`]: { body: page(1, 100) },
    [`GET ${REPOS}2`]: { body: [{ full_name: "luz/so-na-pagina-2", private: true }] },
    "GET /repos/luz/so-na-pagina-2/issues?state=open&per_page=100&sort=created&direction=desc": { body: [] },
  });
  const r = await run(post({ action: "list", repo: "LUZ/so-na-pagina-2" }), deps({ fetch: fn, repos: [] }));
  assertEquals(r.status, 200, r.text);
  assertEquals(r.json, []);
  assertEquals(calls.length, 3);
  // fora da lista continua 403
  const outro = await run(post({ action: "list", repo: "luz/nao-existe" }), deps({ fetch: fn, repos: [] }));
  assertEquals(outro.status, 403);
});

Deno.test("list filtra pull requests, mapeia campos e devolve no máximo 30", async () => {
  const issues = [
    { number: 9, title: "PR disfarçado", state: "open", pull_request: {}, labels: [], created_at: "2026-10-01T00:00:00Z", html_url: "u9", comments: 0 },
    {
      number: 8,
      title: "Bug no widget",
      state: "open",
      labels: [{ name: "bug" }, "texto-solto"],
      created_at: "2026-10-02T10:00:00Z",
      html_url: "https://github.com/luz/app/issues/8",
      comments: 3,
    },
    ...Array.from({ length: 40 }, (_, i) => ({
      number: 100 + i,
      title: `t${i}`,
      state: "open",
      labels: [],
      created_at: "2026-09-01T00:00:00Z",
      html_url: `https://github.com/luz/app/issues/${100 + i}`,
      comments: 0,
    })),
  ];
  const { fn, calls } = fakeFetch({ "GET /repos/luz/app/issues?state=open&per_page=100&sort=created&direction=desc": { body: issues } });
  const r = await run(post({ action: "list", repo: "luz/app", state: "open" }), deps({ fetch: fn }));
  assertEquals(r.status, 200);
  assertEquals(r.json.length, 30);
  assertEquals(r.json[0], {
    number: 8,
    title: "Bug no widget",
    state: "open",
    labels: ["bug", "texto-solto"],
    createdAt: "2026-10-02T10:00:00Z",
    url: "https://github.com/luz/app/issues/8",
    comments: 3,
  });
  assert(!r.json.some((i: { number: number }) => i.number === 9));
  assertEquals(calls.length, 1);
});

Deno.test("list rejeita estado inválido; repo fora da lista permitida nunca chega ao GitHub", async () => {
  const { fn, calls } = fakeFetch({});
  const ruim = await run(post({ action: "list", repo: "luz/app", state: "deletada" }), deps({ fetch: fn }));
  assertEquals(ruim.status, 400);
  for (const repo of ["alheio/segredo", "luz/app/../../x", "luz", "", 5, "../user"]) {
    const r = await run(post({ action: "list", repo, state: "open" }), deps({ fetch: fn }));
    assert(r.status === 400 || r.status === 403, `repo ${repo} => ${r.status}`);
  }
  assertEquals(calls.length, 0);
});

Deno.test("repo é comparado sem diferenciar maiúsculas e usa o nome canônico", async () => {
  const { fn, calls } = fakeFetch({ "GET /repos/luz/app/labels?per_page=100": { body: [{ name: "bug" }, { name: "ideia" }] } });
  const r = await run(post({ action: "labels", repo: "LUZ/App" }), deps({ fetch: fn }));
  assertEquals(r.json, ["bug", "ideia"]);
  assertEquals(calls[0].url, "https://api.github.com/repos/luz/app/labels?per_page=100");
});

Deno.test("create valida título/descrição/rótulos e devolve {number,url}", async () => {
  const { fn, calls } = fakeFetch({
    "POST /repos/luz/app/issues": { status: 201, body: { number: 12, html_url: "https://github.com/luz/app/issues/12" } },
  });
  const ok = await run(
    post({ action: "create", repo: "luz/app", title: "  Corrigir login ", body: "detalhes", labels: ["bug"] }),
    deps({ fetch: fn }),
  );
  assertEquals(ok.status, 200);
  assertEquals(ok.json, { number: 12, url: "https://github.com/luz/app/issues/12" });
  assertEquals(calls[0].body, { title: "Corrigir login", body: "detalhes", labels: ["bug"] });

  const before = calls.length;
  const cases: unknown[] = [
    { title: "" },
    { title: "   " },
    { title: "x".repeat(257) },
    { title: "ok", body: "y".repeat(65537) },
    { title: "ok", labels: "bug" },
    { title: "ok", labels: [1] },
  ];
  for (const extra of cases) {
    const r = await run(post({ action: "create", repo: "luz/app", ...(extra as object) }), deps({ fetch: fn }));
    assertEquals(r.status, 400, JSON.stringify(extra).slice(0, 40));
  }
  assertEquals(calls.length, before);

  // limites exatos passam; sem body/labels não envia os campos
  const limite = await run(post({ action: "create", repo: "luz/app", title: "x".repeat(256) }), deps({ fetch: fn }));
  assertEquals(limite.status, 200);
  assertEquals(Object.keys(calls.at(-1)!.body as object), ["title"]);
});

Deno.test("set_state e comment chamam o endpoint certo e validam entradas", async () => {
  const { fn, calls } = fakeFetch({
    "PATCH /repos/luz/app/issues/8": { body: { number: 8 } },
    "POST /repos/luz/app/issues/8/comments": { status: 201, body: { id: 1 } },
  });
  const a = await run(post({ action: "set_state", repo: "luz/app", number: 8, state: "closed" }), deps({ fetch: fn }));
  assertEquals(a.json, { ok: true });
  assertEquals(calls[0].body, { state: "closed" });
  const b = await run(post({ action: "comment", repo: "luz/app", number: 8, body: "Feito." }), deps({ fetch: fn }));
  assertEquals(b.json, { ok: true });
  assertEquals(calls[1].body, { body: "Feito." });

  const before = calls.length;
  for (
    const ruim of [
      { action: "set_state", repo: "luz/app", number: 8, state: "all" },
      { action: "set_state", repo: "luz/app", number: 0, state: "open" },
      { action: "set_state", repo: "luz/app", number: "8/../9", state: "open" },
      { action: "set_state", repo: "luz/app", number: 1.5, state: "open" },
      { action: "comment", repo: "luz/app", number: 8, body: "  " },
      { action: "comment", repo: "luz/app", number: 8, body: "z".repeat(65537) },
    ]
  ) {
    assertEquals((await run(post(ruim), deps({ fetch: fn }))).status, 400, JSON.stringify(ruim));
  }
  assertEquals(calls.length, before);
});

Deno.test("erros do GitHub viram {error} em pt-BR sem vazar token nem corpo bruto", async () => {
  const casos: [number, number, RegExp][] = [
    [401, 502, /token/i],
    [403, 502, /permiss|limite/i],
    [404, 404, /não encontrad/i],
    [422, 422, /recusou/i],
    [500, 502, /GitHub/],
  ];
  for (const [gh, esperado, rx] of casos) {
    const { fn } = fakeFetch({ "GET /repos/luz/app/labels?per_page=100": { status: gh, body: { message: `detalhe interno ${TOKEN}` } } });
    const r = await run(post({ action: "labels", repo: "luz/app" }), deps({ fetch: fn }));
    assertEquals(r.status, esperado, `gh ${gh}`);
    assert(rx.test(r.json.error), r.json.error);
    assert(!r.text.includes(TOKEN) && !r.text.includes("detalhe interno"));
  }
  const { fn } = fakeFetch({ "GET /repos/luz/app/labels?per_page=100": new Error("rede caiu") });
  const r = await run(post({ action: "labels", repo: "luz/app" }), deps({ fetch: fn }));
  assertEquals(r.status, 502);
  assert(/GitHub/.test(r.json.error));
});
