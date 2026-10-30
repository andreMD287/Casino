// Prueba de punta a punta de la autenticación SRP-6a contra la BD real (André).
// Usa el mismo núcleo que las Server Actions (src/server/auth/nucleo.ts) y la librería del navegador.
//
//   npm run probar:auth      (requiere la BD creada con ./db/run_all.sh y .env.local)
//
// La app se conecta como casino_app. Para simular el paso del tiempo (desafío o sesión vencidos)
// se usa una segunda conexión con el superusuario de PGUSER/PGPASSWORD.
import { config } from 'dotenv';
import { randomBytes } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import * as srp from 'secure-remote-password/client';
import {
  crearCamposSeguros, loginPaso1Nucleo, loginPaso2Nucleo, rolPermitido, sha256Hex, verificarCamposSeguros,
  type ExitoPaso2,
} from '../src/server/auth/nucleo';
import { FalloConCommit } from '../src/server/errores';

config({ path: '.env.local' });
config();

const app = new Pool({ connectionString: process.env.DATABASE_URL, max: 4 });
const admin = new Pool({ database: 'casino', max: 1 }); // PGHOST, PGPORT, PGUSER, PGPASSWORD del entorno
const SECRETO = process.env.SECRETO_SERVIDOR ?? '';

let ok = 0;
let fallo = 0;
function verifica(desc: string, cond: boolean, detalle = '') {
  if (cond) { ok++; console.log(`[OK] ${desc}`); } else { fallo++; console.log(`[FALLO] ${desc} ${detalle}`); }
}

type Q = (sql: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

/** Igual que withTx de src/server/db.ts, pero sin 'server-only'. */
async function tx<T>(usuarioId: number | null, fn: (q: Q) => Promise<T>): Promise<T> {
  const c: PoolClient = await app.connect();
  try {
    await c.query('BEGIN');
    if (usuarioId !== null) await c.query("SELECT set_config('app.usuario_id', $1, true)", [String(usuarioId)]);
    const r = await fn(async (sql, params) => (await c.query(sql, params)).rows);
    await c.query('COMMIT');
    return r;
  } catch (e) {
    await c.query('ROLLBACK');
    throw e;
  } finally {
    c.release();
  }
}

async function codigoDeError(p: Promise<unknown>): Promise<string> {
  try { await p; return 'sin error'; } catch (e) { return String((e as { code?: string }).code ?? e); }
}

/** Login completo como lo hace srp-cliente.ts + las acciones. */
async function login(usuario: string, clave: string) {
  const efimero = srp.generateEphemeral();
  const p1 = await tx(null, (q) => loginPaso1Nucleo(q, usuario, efimero.public, SECRETO));
  const sesion = srp.deriveSession(efimero.secret, p1.B, p1.salt, usuario, srp.derivePrivateKey(p1.salt, usuario, clave));
  const inicio = performance.now();
  const p2 = await tx(null, (q) => loginPaso2Nucleo(q, p1.idDesafio, sesion.proof, SECRETO));
  const ms = performance.now() - inicio;
  let m2Valido = false;
  if (!(p2 instanceof FalloConCommit)) {
    try { srp.verifySession(efimero.public, sesion, p2.M2); m2Valido = true; } catch { m2Valido = false; }
  }
  return { p1, p2, ms, m2Valido, M1: sesion.proof };
}

async function registrar(usuario: string, clave: string) {
  const salt = srp.generateSalt();
  const verificador = srp.deriveVerifier(srp.derivePrivateKey(salt, usuario, clave));
  return tx(null, (q) => q('SELECT * FROM casino.fn_registrar_jugador($1, $2, $3, $4, $5, $6)',
    [`P-${randomBytes(4).toString('hex')}`, 'Prueba Auth', '1990-01-01', usuario, salt, verificador]));
}

async function main() {
  if (SECRETO.length < 32) throw new Error('Falta SECRETO_SERVIDOR en .env.local');
  const sufijo = randomBytes(3).toString('hex');
  const usuario = `prueba_${sufijo}`;
  const clave = 'Clave-Secreta-123';

  // 1. Registro y login correctos
  const [reg] = await registrar(usuario, clave);
  verifica('registro de jugador', typeof reg?.codigo === 'string', JSON.stringify(reg));
  const bien = await login(usuario, clave);
  const exito = bien.p2 instanceof FalloConCommit ? null : (bien.p2 as ExitoPaso2);
  verifica('login correcto: crea sesión con rol jugador', exito?.rol === 'jugador', JSON.stringify(bien.p2));
  verifica('login correcto: el cliente verifica M2 (autenticación mutua)', bien.m2Valido);
  const filasSesion = exito ? (await app.query('SELECT * FROM casino.fn_obtener_sesion($1)', [sha256Hex(exito.token)])).rows : [];
  verifica('la BD guarda SHA-256(token) y con él se recupera la sesión', filasSesion[0]?.usuario === usuario);
  const crudo = (await admin.query('SELECT count(*)::int AS n FROM casino.sesiones WHERE token_hash = $1', [exito?.token ?? ''])).rows[0].n;
  verifica('el token en claro no está guardado en la BD', crudo === 0);

  // 2. Clave incorrecta
  const mal = await login(usuario, 'otra-clave');
  verifica('clave incorrecta → CA004', mal.p2 instanceof FalloConCommit && mal.p2.codigo === 'CA004');

  // 3. Usuario inexistente: misma forma de respuesta y mismo error
  const fantasma = `nadie_${sufijo}`;
  const inex = await login(fantasma, 'lo-que-sea');
  const inex2 = await tx(null, (q) => loginPaso1Nucleo(q, fantasma, srp.generateEphemeral().public, SECRETO));
  verifica('usuario inexistente: el paso 1 responde igual (salt de 64 hex, B, idDesafio)',
    /^[0-9a-f]{64}$/.test(inex.p1.salt) && inex.p1.B.length > 500 && /^[0-9a-f-]{36}$/.test(inex.p1.idDesafio));
  verifica('usuario inexistente: el salt señuelo es estable entre intentos', inex.p1.salt === inex2.salt);
  verifica('usuario inexistente → el mismo CA004 que una clave incorrecta',
    inex.p2 instanceof FalloConCommit && inex.p2.codigo === 'CA004' && inex.p2.mensaje === (mal.p2 as FalloConCommit).mensaje);
  // Tiempo del paso 2 (informativo): usuario inexistente vs. clave incorrecta (3 intentos cada uno).
  const promedio = async (u: string) => {
    let total = 0;
    for (let i = 0; i < 3; i++) total += (await login(u, `x${i}`)).ms;
    return Math.round(total / 3);
  };
  console.log(`      (paso 2: usuario inexistente ≈ ${await promedio(fantasma)} ms, clave incorrecta ≈ ${await promedio(usuario)} ms)`);

  // 4. Reutilizar un desafío
  const reuso = await codigoDeError(tx(null, (q) => loginPaso2Nucleo(q, bien.p1.idDesafio, bien.M1, SECRETO)));
  verifica('reutilizar un desafío ya usado → CA005', reuso === 'CA005', reuso);

  // 5. Desafío vencido (se adelanta el reloj con el superusuario)
  const ef = srp.generateEphemeral();
  const p1v = await tx(null, (q) => loginPaso1Nucleo(q, usuario, ef.public, SECRETO));
  await admin.query("UPDATE casino.desafios_login SET expira_en = now() - interval '1 second' WHERE id = $1", [p1v.idDesafio]);
  const sv = srp.deriveSession(ef.secret, p1v.B, p1v.salt, usuario, srp.derivePrivateKey(p1v.salt, usuario, clave));
  const vencido = await codigoDeError(tx(null, (q) => loginPaso2Nucleo(q, p1v.idDesafio, sv.proof, SECRETO)));
  verifica('desafío vencido (más de 2 minutos) → CA005', vencido === 'CA005', vencido);

  // 6. Sesión cerrada y sesión vencida
  const otra = await login(usuario, clave);
  const tokenOtra = (otra.p2 as ExitoPaso2).token;
  await app.query('SELECT casino.fn_cerrar_sesion($1)', [sha256Hex(exito!.token)]);
  verifica('sesión cerrada: ya no es válida', (await app.query('SELECT * FROM casino.fn_obtener_sesion($1)', [sha256Hex(exito!.token)])).rowCount === 0);
  await admin.query("UPDATE casino.sesiones SET creada_en = now() - interval '9 hours', expira_en = now() - interval '1 hour' WHERE token_hash = $1", [sha256Hex(tokenOtra)]);
  verifica('sesión vencida (más de 8 horas): ya no es válida', (await app.query('SELECT * FROM casino.fn_obtener_sesion($1)', [sha256Hex(tokenOtra)])).rowCount === 0);

  // 7. Acción con un rol no permitido: se rechaza en el servidor aunque la UI no la muestre
  verifica('capa 2 (crearAccion): jugador no pasa el filtro de una acción de crupier', !rolPermitido('jugador', ['crupier']));
  const uid = Number((await app.query('SELECT id FROM casino.fn_srp_datos_login($1)', [usuario])).rows[0].id);
  const rolBd = await codigoDeError(tx(uid, (q) => q('SELECT casino.fn_abrir_ronda(1)')));
  verifica('capa 3 (BD): un jugador que llama fn_abrir_ronda → CA002', rolBd === 'CA002', rolBd);
  const tabla = await codigoDeError(app.query('UPDATE casino.jugadores SET saldo = 999999'));
  verifica('casino_app no puede modificar tablas directamente (42501)', tabla === '42501', tabla);

  // 8. Firma del formulario seguro
  const canal = randomBytes(32).toString('hex');
  const campos = crearCamposSeguros(canal);
  verifica('formulario seguro: firma válida se acepta', verificarCamposSeguros(canal, campos));
  const alterada = { ...campos, firma: campos.firma.replace(/^./, (c) => (c === '0' ? '1' : '0')) };
  verifica('formulario seguro: firma alterada → rechazada (CA007)', !verificarCamposSeguros(canal, alterada));
  verifica('formulario seguro: fechahora alterada → rechazada', !verificarCamposSeguros(canal, { ...campos, fechahora: new Date(Date.now() - 1000).toISOString() }));
  verifica('formulario seguro: firma de otra sesión (otro canal) → rechazada', !verificarCamposSeguros(randomBytes(32).toString('hex'), campos));
  const viejo = crearCamposSeguros(canal, new Date(Date.now() - 31 * 60_000));
  verifica('formulario seguro: más de 30 minutos → rechazado', !verificarCamposSeguros(canal, viejo));

  // 9. Bloqueo por fuerza bruta: 5 fallos en 15 minutos
  const victima = `bloqueo_${sufijo}`;
  await registrar(victima, clave);
  for (let i = 0; i < 5; i++) await login(victima, `mala-${i}`);
  const bloqueo = await codigoDeError(tx(null, (q) => loginPaso1Nucleo(q, victima, srp.generateEphemeral().public, SECRETO)));
  verifica('5 intentos fallidos en 15 minutos → CA006', bloqueo === 'CA006', bloqueo);

  console.log(`\nResultado: OK=${ok}  FALLO=${fallo}`);
}

main()
  .catch((e) => { console.error(e); fallo++; })
  .finally(async () => {
    await app.end();
    await admin.end();
    process.exit(fallo > 0 ? 1 : 0);
  });
