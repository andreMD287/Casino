import 'server-only';
import { cache } from 'react';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import type { Rol, Sesion } from '@/lib/contrato';
import { pool } from '@/server/db';
import { COOKIE_CANAL, COOKIE_SESION, sha256Hex } from '@/server/auth/nucleo';
import { sesionMock } from '@/server/mocks/auth';

/** Sesión con el canal (secreto para firmar formularios). El canal nunca se envía al navegador. */
export type SesionInterna = Sesion & { canal: string };

export function modoMock(): boolean {
  return process.env.MODO_MOCK === '1';
}

/** Lee la cookie, calcula SHA-256(token) y busca la sesión vigente en la BD. Se memoriza por petición. */
export const obtenerSesionInterna = cache(async (): Promise<SesionInterna | null> => {
  if (modoMock()) return sesionMock();
  const token = (await cookies()).get(COOKIE_SESION)?.value;
  if (!token) return null;
  const { rows } = await pool.query<{ usuario_id: number; usuario: string; nombre: string; rol: Rol; canal: string }>(
    'SELECT usuario_id, usuario, nombre, rol, canal FROM casino.fn_obtener_sesion($1)',
    [sha256Hex(token)],
  );
  const fila = rows[0];
  if (!fila) return null;
  return { usuarioId: fila.usuario_id, usuario: fila.usuario, nombre: fila.nombre, rol: fila.rol, canal: fila.canal };
});

/** Canal para firmar formularios: el de la sesión o, sin sesión, el anónimo que pone el proxy. */
export async function obtenerCanal(): Promise<string | null> {
  const sesion = await obtenerSesionInterna();
  if (sesion) return sesion.canal;
  return (await cookies()).get(COOKIE_CANAL)?.value ?? null;
}

export async function obtenerSesion(): Promise<Sesion | null> {
  const s = await obtenerSesionInterna();
  return s ? { usuarioId: s.usuarioId, usuario: s.usuario, nombre: s.nombre, rol: s.rol } : null;
}

/** Para layouts y páginas: sin sesión → /login; rol no permitido → /prohibido. Sin roles = cualquier rol. */
export async function exigirSesion(...roles: Rol[]): Promise<Sesion> {
  const sesion = await obtenerSesion();
  if (!sesion) redirect('/login');
  if (roles.length > 0 && !roles.includes(sesion.rol)) redirect('/prohibido');
  return sesion;
}
