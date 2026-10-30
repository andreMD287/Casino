'use server';
// Acciones de autenticación (André). Login Zero Knowledge con SRP-6a + SHA-256.
import { cookies } from 'next/headers';
import { z } from 'zod';
import type { CamposSeguros } from '@/lib/contrato';
import { crearAccion, zCredenciales, zSeguro } from '@/server/accion';
import { pool } from '@/server/db';
import { COOKIE_SESION, crearCamposSeguros, loginPaso1Nucleo, loginPaso2Nucleo, sha256Hex } from '@/server/auth/nucleo';
import { modoMock, obtenerCanal } from '@/server/auth/sesion';
import { FalloConCommit } from '@/server/errores';
import * as mock from '@/server/mocks/auth';

const zHex = z.string().regex(/^[0-9a-f]{1,1024}$/i, 'valor hexadecimal').transform((s) => s.toLowerCase());

function secreto(): string {
  const s = process.env.SECRETO_SERVIDOR;
  if (!s || s.length < 32) throw new Error('SECRETO_SERVIDOR no está configurado (32+ caracteres)');
  return s;
}

/** Paso 1 de SRP: recibe (usuario, A) y responde (idDesafio, salt, B). Usuario inexistente → señuelo. */
export const loginPaso1 = crearAccion(
  { roles: 'publica', seguro: false, args: z.tuple([z.string().min(1).max(60), zHex]), mock: mock.loginPaso1 },
  async ({ q }, usuario, A) => loginPaso1Nucleo(q, usuario, A, secreto()),
);

/** Paso 2 de SRP: verifica M1, crea la sesión (cookie httpOnly) y devuelve M2 para que el cliente verifique al servidor. */
export const loginPaso2 = crearAccion(
  { roles: 'publica', seguro: false, args: z.tuple([z.uuid(), zHex]), mock: mock.loginPaso2 },
  async ({ q }, idDesafio, M1) => {
    const r = await loginPaso2Nucleo(q, idDesafio, M1, secreto());
    if (r instanceof FalloConCommit) return r;
    (await cookies()).set(COOKIE_SESION, r.token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      path: '/',
      expires: r.expira,
    });
    return { M2: r.M2, rol: r.rol };
  },
);

/** Cierra la sesión en la BD y borra la cookie. */
export async function cerrarSesion(): Promise<void> {
  const almacen = await cookies();
  const token = almacen.get(COOKIE_SESION)?.value;
  if (token && !modoMock()) {
    try {
      await pool.query('SELECT casino.fn_cerrar_sesion($1)', [sha256Hex(token)]);
    } catch (err) {
      console.error('[cerrarSesion]', err);
    }
  }
  almacen.delete(COOKIE_SESION);
}

/** Campos del formulario seguro: fechahora ISO y firma = SHA-256(canal + fechahora). */
export async function obtenerCamposSeguros(): Promise<CamposSeguros> {
  return crearCamposSeguros((await obtenerCanal()) ?? '');
}

/** Registro público de jugadores. Las credenciales (salt, verificador) se derivan en el navegador. */
export const registrarJugador = crearAccion(
  {
    roles: 'publica',
    seguro: true,
    args: z.tuple([
      z.object({
        documento: z.string().trim().min(3).max(20),
        nombre: z.string().trim().min(3).max(100),
        fechaNacimiento: z.iso.date(),
      }),
      zCredenciales,
      zSeguro,
    ]),
    mock: mock.registrarJugador,
  },
  async ({ q }, datos, cred) => {
    const [fila] = await q<{ jugador_id: number; codigo: string }>(
      'SELECT jugador_id, codigo FROM casino.fn_registrar_jugador($1, $2, $3, $4, $5, $6)',
      [datos.documento, datos.nombre, datos.fechaNacimiento, cred.usuario, cred.salt, cred.verificador],
    );
    return { jugadorId: fila.jugador_id, codigo: fila.codigo };
  },
);
