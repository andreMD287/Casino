// Mock de autenticación (MODO_MOCK=1). El login hace SRP-6a de verdad contra usuarios en memoria
// (clave Casino2026*), así el formulario de login funciona igual que en modo real.
// La sesión simulada siempre tiene el rol de MOCK_ROL.
import { randomUUID } from 'node:crypto';
import { cookies } from 'next/headers';
import * as srpCliente from 'secure-remote-password/client';
import * as srpServer from 'secure-remote-password/server';
import type { CamposSeguros, Credenciales, Rol } from '@/lib/contrato';
import { ErrorCasino } from '@/server/errores';
import { COOKIE_SESION, normalizarUsuario } from '@/server/auth/nucleo';
import { mockEmpleados, mockJugadorDeUsuario, mockJugadores, mockUsuarios, siguienteId } from '@/server/mocks/datos';
import type { CtxMock } from '@/server/accion';

const CLAVE_PRUEBA = 'Casino2026*';
const USUARIO_POR_ROL: Record<Rol, number> = { administrador: 1, crupier: 2, supervisor: 6, jugador: 8 };

function rolMock(): Rol {
  const rol = process.env.MOCK_ROL as Rol | undefined;
  return rol && rol in USUARIO_POR_ROL ? rol : 'administrador';
}

/** Sesión falsa con el rol de MOCK_ROL (incluye un canal fijo para firmar formularios). */
export function sesionMock() {
  const rol = rolMock();
  const u = mockUsuarios.find((x) => x.id === USUARIO_POR_ROL[rol])!;
  const nombre = mockEmpleados.find((e) => e.usuario === u.usuario)?.nombre
    ?? mockJugadores.find((j) => j.id === mockJugadorDeUsuario[u.id])?.nombre ?? u.usuario;
  return { usuarioId: u.id, usuario: u.usuario, nombre, rol, canal: 'canal-mock-0123456789abcdef0123456789abcdef' };
}

// Credenciales SRP en memoria (se calculan la primera vez que se usan).
const credenciales = new Map<string, { salt: string; verificador: string }>();
function credencialesDe(usuario: string) {
  if (!mockUsuarios.some((u) => u.usuario === usuario) && !credenciales.has(usuario)) return null;
  if (!credenciales.has(usuario)) {
    const salt = srpCliente.generateSalt();
    credenciales.set(usuario, { salt, verificador: srpCliente.deriveVerifier(srpCliente.derivePrivateKey(salt, usuario, CLAVE_PRUEBA)) });
  }
  return credenciales.get(usuario)!;
}

const desafios = new Map<string, { usuario: string; A: string; b: string; usado: boolean }>();

export async function loginPaso1(_ctx: CtxMock, usuarioCrudo: string, A: string) {
  const usuario = normalizarUsuario(usuarioCrudo);
  const cred = credencialesDe(usuario) ?? { salt: '00'.repeat(32), verificador: 'ab'.repeat(32) };
  const efimero = srpServer.generateEphemeral(cred.verificador);
  const idDesafio = randomUUID();
  desafios.set(idDesafio, { usuario, A, b: efimero.secret, usado: false });
  return { idDesafio, salt: cred.salt, B: efimero.public };
}

export async function loginPaso2(_ctx: CtxMock, idDesafio: string, M1: string): Promise<{ M2: string; rol: Rol }> {
  const d = desafios.get(idDesafio);
  if (!d || d.usado) throw new ErrorCasino('CA005', 'El inicio de sesión venció o ya se usó; intenta de nuevo');
  d.usado = true;
  const cred = credencialesDe(d.usuario);
  try {
    if (!cred) throw new Error('señuelo');
    const sesion = srpServer.deriveSession(d.b, d.A, cred.salt, d.usuario, cred.verificador, M1);
    (await cookies()).set(COOKIE_SESION, 'mock', { httpOnly: true, sameSite: 'strict', path: '/', maxAge: 8 * 3600 });
    return { M2: sesion.proof, rol: rolMock() };
  } catch {
    throw new ErrorCasino('CA004', 'Usuario o clave incorrectos');
  }
}

export async function registrarJugador(
  _ctx: CtxMock,
  datos: { documento: string; nombre: string; fechaNacimiento: string },
  cred: Credenciales,
  _seguro: CamposSeguros,
) {
  if (mockUsuarios.some((u) => u.usuario === cred.usuario)) throw new ErrorCasino('CA003', `El usuario "${cred.usuario}" ya existe`);
  if (mockJugadores.some((j) => j.documento === datos.documento)) throw new ErrorCasino('CA013', `Ya existe un jugador con el documento ${datos.documento}`);
  const usuarioId = siguienteId(mockUsuarios);
  mockUsuarios.push({ id: usuarioId, usuario: cred.usuario, rol: 'jugador' });
  credenciales.set(cred.usuario, { salt: cred.salt, verificador: cred.verificador });
  const jugadorId = siguienteId(mockJugadores);
  const codigo = `J-${String(jugadorId).padStart(6, '0')}`;
  mockJugadores.push({ id: jugadorId, codigo, nombre: datos.nombre, documento: datos.documento, fechaNacimiento: datos.fechaNacimiento,
    saldo: '0.00', estado: 'Activo', suspendidoHasta: null, esEmpleado: false, activo: true });
  mockJugadorDeUsuario[usuarioId] = jugadorId;
  return { jugadorId, codigo };
}
