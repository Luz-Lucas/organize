import { randomUUID } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any
type Filter = (r: Row) => boolean;

/** Palpite mínimo de seção: imita o gatilho do banco só o bastante para os testes. */
function guessSection(name: string): string {
  const f = name.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
  if (f.includes('leite')) return 'frios';
  if (f.includes('pao')) return 'padaria';
  return 'outros';
}

/** Banco falso em memória que implementa só o trecho do supabase-js que as ferramentas usam. */
export class FakeDb {
  readonly tables = new Map<string, Row[]>();
  /** Inserções feitas, na ordem (para checar o que foi enviado ao banco). */
  readonly inserts: Array<{ table: string; row: Row }> = [];

  rows(table: string): Row[] {
    let t = this.tables.get(table);
    if (!t) this.tables.set(table, (t = []));
    return t;
  }

  seed(table: string, rows: Row[]): Row[] {
    const out = rows.map((r) => ({ id: randomUUID(), created_at: new Date().toISOString(), ...r }));
    this.rows(table).push(...out);
    return out;
  }

  from(table: string): Query {
    return new Query(this, table);
  }

  client(): SupabaseClient {
    return this as unknown as SupabaseClient;
  }

  /** Defaults e gatilhos do esquema. */
  applyInsert(table: string, input: Row): Row {
    const r: Row = { id: randomUUID(), created_at: new Date().toISOString(), ...input };
    if (table === 'shopping_items') {
      r.quantity ??= '';
      r.checked ??= false;
      r.position ??= 0;
      r.section ??= guessSection(r.name);
    } else if (table === 'shopping_lists') {
      r.position ??= 0;
      const dup = this.rows(table).some((x) => x.user_id === r.user_id && x.name.toLowerCase() === String(r.name).toLowerCase());
      if (dup) throw Object.assign(new Error('duplicate'), { code: '23505' });
    } else if (table === 'workouts') {
      r.position ??= 0;
    } else if (table === 'workout_exercises') {
      r.sets ??= 3;
      r.reps ??= '10';
      r.load_kg ??= null;
      r.rest_seconds ??= 90;
      r.notes ??= '';
      r.position ??= 0;
    }
    return r;
  }
}

class Query implements PromiseLike<{ data: any; error: any }> { // eslint-disable-line @typescript-eslint/no-explicit-any
  private filters: Filter[] = [];
  private mode: 'select' | 'insert' | 'update' | 'delete' = 'select';
  private payload: Row | Row[] | null = null;
  private returning = false;
  private orders: Array<[string, boolean]> = [];
  private max = Infinity;
  private one: 'single' | 'maybe' | null = null;

  constructor(private readonly db: FakeDb, private readonly table: string) {}

  select(_cols?: string): this { // eslint-disable-line @typescript-eslint/no-unused-vars
    if (this.mode !== 'select') this.returning = true;
    return this;
  }
  insert(p: Row | Row[]): this { this.mode = 'insert'; this.payload = p; return this; }
  update(p: Row): this { this.mode = 'update'; this.payload = p; return this; }
  delete(): this { this.mode = 'delete'; return this; }
  eq(c: string, v: unknown): this { this.filters.push((r) => r[c] === v); return this; }
  neq(c: string, v: unknown): this { this.filters.push((r) => r[c] !== v); return this; }
  in(c: string, vs: unknown[]): this { this.filters.push((r) => vs.includes(r[c])); return this; }
  gte(c: string, v: unknown): this { this.filters.push((r) => r[c] >= (v as string)); return this; }
  lte(c: string, v: unknown): this { this.filters.push((r) => r[c] <= (v as string)); return this; }
  order(c: string, o: { ascending?: boolean } = {}): this { this.orders.push([c, o.ascending !== false]); return this; }
  limit(n: number): this { this.max = n; return this; }
  single(): this { this.one = 'single'; return this; }
  maybeSingle(): this { this.one = 'maybe'; return this; }

  private run(): { data: any; error: any } { // eslint-disable-line @typescript-eslint/no-explicit-any
    const all = this.db.rows(this.table);
    const match = (r: Row) => this.filters.every((f) => f(r));
    let out: Row[];
    try {
      if (this.mode === 'insert') {
        const list = Array.isArray(this.payload) ? this.payload : [this.payload!];
        const made = list.map((p) => this.db.applyInsert(this.table, p));
        for (let i = 0; i < made.length; i++) this.db.inserts.push({ table: this.table, row: list[i] });
        all.push(...made);
        out = made;
      } else if (this.mode === 'update') {
        out = all.filter(match);
        for (const r of out) Object.assign(r, this.payload);
      } else if (this.mode === 'delete') {
        out = all.filter(match);
        this.db.tables.set(this.table, all.filter((r) => !match(r)));
        // cascatas usadas nos testes
        if (this.table === 'workouts') {
          const ids = new Set(out.map((r) => r.id));
          this.db.tables.set('workout_exercises', this.db.rows('workout_exercises').filter((r) => !ids.has(r.workout_id)));
        }
      } else {
        out = all.filter(match);
      }
    } catch (e) {
      return { data: null, error: { code: (e as { code?: string }).code ?? 'XX000' } };
    }
    for (const [c, asc] of [...this.orders].reverse()) {
      out = [...out].sort((a, b) => (a[c] < b[c] ? -1 : a[c] > b[c] ? 1 : 0) * (asc ? 1 : -1));
    }
    out = out.slice(0, this.max).map((r) => ({ ...r }));
    if (this.mode !== 'select' && !this.returning) return { data: null, error: null };
    if (this.one === 'single') return out.length === 1 ? { data: out[0], error: null } : { data: null, error: { code: 'PGRST116' } };
    if (this.one === 'maybe') return { data: out[0] ?? null, error: null };
    return { data: out, error: null };
  }

  then<R1 = { data: any; error: any }, R2 = never>( // eslint-disable-line @typescript-eslint/no-explicit-any
    onfulfilled?: ((v: { data: any; error: any }) => R1 | PromiseLike<R1>) | null, // eslint-disable-line @typescript-eslint/no-explicit-any
    onrejected?: ((e: unknown) => R2 | PromiseLike<R2>) | null,
  ): PromiseLike<R1 | R2> {
    return Promise.resolve().then(() => this.run()).then(onfulfilled, onrejected);
  }
}
