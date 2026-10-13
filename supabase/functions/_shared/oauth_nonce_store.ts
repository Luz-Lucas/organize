// NonceStore sobre o Postgres (service role): a função consume_oauth_nonce insere o nonce e devolve
// false se ele já existia; ela também apaga nonces com mais de 1 dia (o state vale só 10 minutos).
import type { NonceStore } from "./gmail.ts";
import type { createAdminClient } from "./gmail_store.ts";

type Db = ReturnType<typeof createAdminClient>;

export function createNonceStore(db: Db): NonceStore {
  return {
    async consume(nonce) {
      const { data, error } = await db.rpc("consume_oauth_nonce", { p_nonce: nonce });
      if (error) throw new Error("db:consumeNonce"); // sem detalhes do erro
      return data === true;
    },
  };
}
