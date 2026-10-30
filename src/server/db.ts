import 'server-only';
import { Pool, types, type PoolClient, type QueryResultRow } from 'pg';

// ---- Parsers de tipos ----
// numeric (1700) se queda como string: el dinero nunca pasa por float.
types.setTypeParser(1700, (v) => v);
// bigint (20): los id caben de sobra en un number de JS.
types.setTypeParser(20, (v) => Number.parseInt(v, 10));
// date (1082): se deja 'YYYY-MM-DD' tal cual, sin zona horaria.
types.setTypeParser(1082, (v) => v);
// timestamptz (1184): string ISO en UTC.
const parsearTimestamptz = types.getTypeParser(1184);
types.setTypeParser(1184, (v) => (parsearTimestamptz(v) as Date).toISOString());

// ---- Pool ----
// Se guarda en globalThis para que el hot reload de `next dev` no abra un pool nuevo en cada cambio.
const globalConPool = globalThis as unknown as { __casinoPool?: Pool };

function crearPool(): Pool {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 10 });
  pool.on('error', (err) => console.error('[db] error en conexión inactiva', err));
  return pool;
}

export const pool: Pool = globalConPool.__casinoPool ?? crearPool();
if (process.env.NODE_ENV !== 'production') globalConPool.__casinoPool = pool;

export type Consulta = <R extends QueryResultRow = QueryResultRow>(sql: string, params?: unknown[]) => Promise<R[]>;

/**
 * Ejecuta `fn` dentro de una transacción. Si hay usuario, fija `app.usuario_id`
 * solo para esta transacción (equivale a SET LOCAL); las funciones SQL lo leen con fn_actor().
 */
export async function withTx<T>(usuarioId: number | null, fn: (q: Consulta, cliente: PoolClient) => Promise<T>): Promise<T> {
  const cliente = await pool.connect();
  const q: Consulta = async (sql, params) => (await cliente.query(sql, params as unknown[])).rows;
  try {
    await cliente.query('BEGIN');
    if (usuarioId !== null) {
      await cliente.query("SELECT set_config('app.usuario_id', $1, true)", [String(usuarioId)]);
    }
    const resultado = await fn(q, cliente);
    await cliente.query('COMMIT');
    return resultado;
  } catch (err) {
    await cliente.query('ROLLBACK').catch(() => undefined);
    throw err;
  } finally {
    cliente.release();
  }
}
