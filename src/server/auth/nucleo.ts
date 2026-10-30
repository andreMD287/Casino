// Núcleo de autenticación: SRP-6a del lado servidor, tokens de sesión y formulario seguro.
// No importa nada de Next ni 'server-only' para poder probarlo con `tsx` (scripts/probar-auth.ts).
// Recibe una función `q` que ejecuta SQL dentro de la transacción de quien lo llama.
import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import * as srpServer from 'secure-remote-password/server';
import type { CamposSeguros, Rol } from '@/lib/contrato';
import { ERR, FalloConCommit } from '@/server/errores';

export const COOKIE_SESION = 'casino_sesion';
export const COOKIE_CANAL = 'casino_canal';
export const DURACION_SESION_MS = 8 * 60 * 60 * 1000;
export const VIGENCIA_FORMULARIO_MS = 30 * 60 * 1000;

type Q = (sql: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

export function sha256Hex(texto: string): string {
  return createHash('sha256').update(texto, 'utf8').digest('hex');
}

function hmacHex(secreto: string, texto: string): string {
  return createHmac('sha256', secreto).update(texto, 'utf8').digest('hex');
}

export function normalizarUsuario(usuario: string): string {
  return usuario.trim().toLowerCase();
}

export function rolPermitido(rol: Rol, roles: Rol[] | 'publica'): boolean {
  return roles === 'publica' || roles.includes(rol);
}

// ---------- Formulario seguro: firma = SHA-256(canal + fechahora) ----------

export function firmarCampos(canal: string, fechahora: string): string {
  return sha256Hex(canal + fechahora);
}

export function crearCamposSeguros(canal: string, ahora: Date = new Date()): CamposSeguros {
  const fechahora = ahora.toISOString();
  return { fechahora, firma: firmarCampos(canal, fechahora) };
}

export function verificarCamposSeguros(canal: string | null | undefined, campos: CamposSeguros, ahora: number = Date.now()): boolean {
  if (!canal) return false;
  const momento = Date.parse(campos.fechahora);
  if (Number.isNaN(momento)) return false;
  const edad = ahora - momento;
  // Se tolera 1 minuto de reloj adelantado; más allá, o más de 30 minutos de antigüedad, se rechaza.
  if (edad > VIGENCIA_FORMULARIO_MS || edad < -60_000) return false;
  const esperada = Buffer.from(firmarCampos(canal, campos.fechahora), 'hex');
  const recibida = Buffer.from(campos.firma, 'hex');
  return esperada.length === recibida.length && timingSafeEqual(esperada, recibida);
}

// ---------- Tokens ----------

export function generarTokenSesion(): { token: string; tokenHash: string; canal: string } {
  const token = randomBytes(32).toString('base64url');
  return { token, tokenHash: sha256Hex(token), canal: randomBytes(32).toString('hex') };
}

export function generarCanalAnonimo(): string {
  return randomBytes(32).toString('hex');
}

// ---------- SRP-6a ----------

/** Datos falsos y deterministas para un usuario que no existe (respuesta señuelo). */
function senuelo(secreto: string, usuario: string) {
  return {
    salt: hmacHex(secreto, `salt:${usuario}`),
    verificador: hmacHex(secreto, `verificador:${usuario}`),
  };
}

/**
 * Paso 1: el cliente envía (usuario, A). Se responde (idDesafio, salt, B).
 * Si el usuario no existe o está inactivo, la respuesta es un señuelo indistinguible:
 * mismo formato, mismo costo (una exponenciación modular) y también se guarda un desafío.
 */
export async function loginPaso1Nucleo(q: Q, usuarioCrudo: string, A: string, secreto: string) {
  const usuario = normalizarUsuario(usuarioCrudo);
  const filas = await q('SELECT id, salt, verificador FROM casino.fn_srp_datos_login($1)', [usuario]);
  const real = filas[0] as { id: number; salt: string; verificador: string } | undefined;
  const datos = real ?? senuelo(secreto, usuario);
  const efimero = srpServer.generateEphemeral(datos.verificador);
  const [fila] = await q('SELECT casino.fn_guardar_desafio($1, $2, $3, $4) AS id', [
    real ? real.id : null,
    A,
    efimero.public,
    efimero.secret,
  ]);
  return { idDesafio: String(fila.id), salt: datos.salt, B: efimero.public };
}

type DesafioConsumido = {
  usuario_id: number | null;
  usuario: string | null;
  salt: string | null;
  verificador: string | null;
  rol: Rol | null;
  a_publico: string;
  b_secreto: string;
};

export type ExitoPaso2 = { M2: string; rol: Rol; usuarioId: number; token: string; expira: Date };

/**
 * Paso 2: el cliente envía (idDesafio, M1). Si M1 es válido se crea la sesión y se devuelve M2.
 * Cualquier credencial inválida devuelve el mismo fallo CA004, como FalloConCommit para que
 * el desafío quede marcado como fallido (cuenta para el bloqueo por fuerza bruta).
 */
export async function loginPaso2Nucleo(q: Q, idDesafio: string, M1: string, secreto: string): Promise<ExitoPaso2 | FalloConCommit> {
  // Lanza CA005 si el desafío ya se usó o venció.
  const [d] = (await q('SELECT * FROM casino.fn_consumir_desafio($1)', [idDesafio])) as DesafioConsumido[];

  let sesionSrp: { key: string; proof: string } | null = null;
  try {
    if (d.usuario_id === null) {
      // Señuelo: se hace el mismo cálculo para gastar el mismo tiempo; siempre falla.
      const falso = senuelo(secreto, '');
      srpServer.deriveSession(d.b_secreto, d.a_publico, falso.salt, '', falso.verificador, M1);
    } else {
      sesionSrp = srpServer.deriveSession(d.b_secreto, d.a_publico, d.salt!, d.usuario!, d.verificador!, M1);
    }
  } catch {
    sesionSrp = null;
  }

  if (!sesionSrp || d.usuario_id === null || !d.rol) {
    await q('SELECT casino.fn_marcar_desafio($1, false)', [idDesafio]);
    return ERR.credenciales();
  }

  await q('SELECT casino.fn_marcar_desafio($1, true)', [idDesafio]);
  const { token, tokenHash, canal } = generarTokenSesion();
  const expira = new Date(Date.now() + DURACION_SESION_MS);
  await q('SELECT casino.fn_crear_sesion($1, $2, $3, $4)', [d.usuario_id, tokenHash, canal, expira.toISOString()]);
  return { M2: sesionSrp.proof, rol: d.rol, usuarioId: d.usuario_id, token, expira };
}
