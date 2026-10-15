import type { WakeOverride } from './scheduler.js';
import { addDays } from './time.js';

/**
 * Leitor de exceções de data do despertar, tolerante a falhas: se a leitura falhar,
 * devolve o último resultado bom (ou []) e só registra a mensagem do erro, sem dados
 * do usuário. Assim, uma falha ao ler as exceções nunca impede disparar, armar ou cancelar.
 * A janela (-2 a +2 dias em torno de hoje) é a mesma dos runs.
 */
export function createOverridesLoader(
  load: (fromDate: string, toDate: string) => Promise<WakeOverride[]>,
  log: (message: string) => void,
): (today: string) => Promise<WakeOverride[]> {
  let lastGood: WakeOverride[] = [];
  return async (today) => {
    try {
      lastGood = await load(addDays(today, -2), addDays(today, 2));
    } catch (e) {
      log(`exceções de despertar indisponíveis, usando o último resultado: ${(e as Error).message}`);
    }
    return lastGood;
  };
}
