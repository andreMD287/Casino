// Mock de jugadores, riesgo e historial (MODO_MOCK=1). Creado por André en la fase 0; desde ahí es de Andrés.
import type { CamposSeguros, Dinero, Historial, Investigacion, Jugador, Movimiento, Suspension } from '@/lib/contrato';
import type { CtxMock } from '@/server/accion';
import { ErrorCasino } from '@/server/errores';
import {
  centavos, dinero, mockAbonos, mockApuestas, mockConfiguracion, mockInvestigaciones, mockJugadorDeUsuario, mockJugadores,
  mockMovimientos, mockSuspensiones, moverSaldoMock, siguienteId,
} from '@/server/mocks/datos';

const buscar = (id: number) => {
  const j = mockJugadores.find((x) => x.id === id);
  if (!j) throw new ErrorCasino('CA012', 'El jugador no existe');
  return j;
};

function historialDe(jugadorId: number): Historial {
  const jugador = { ...buscar(jugadorId) };
  return {
    jugador,
    apuestas: mockApuestas.filter((a) => a.jugadorId === jugadorId).map((a) => ({ ...a })),
    movimientos: mockMovimientos.filter((m) => m.jugadorId === jugadorId).map(({ jugadorId: _j, ...m }) => m),
    suspensiones: mockSuspensiones.filter((s) => s.jugadorId === jugadorId).map((s) => ({ ...s })),
    investigaciones: mockInvestigaciones.filter((i) => i.jugadorId === jugadorId).map((i) => ({ ...i })),
    deudaEmpleado: jugador.esEmpleado ? '0.00' : null,
  };
}

export async function listarJugadores(_ctx: CtxMock, filtro?: string): Promise<Jugador[]> {
  const f = filtro?.trim().toLowerCase();
  return mockJugadores
    .filter((j) => !f || j.nombre.toLowerCase().includes(f) || j.codigo.toLowerCase().includes(f) || j.documento.includes(f))
    .map((j) => ({ ...j }));
}

export async function obtenerHistorial(_ctx: CtxMock, jugadorId: number): Promise<Historial> {
  return historialDe(jugadorId);
}

export async function miHistorial(ctx: CtxMock): Promise<Historial> {
  const id = mockJugadorDeUsuario[ctx.sesion?.usuarioId ?? -1];
  if (!id) throw new ErrorCasino('CA304', 'Tu usuario no tiene ficha de jugador');
  return historialDe(id);
}

export async function actualizarJugador(_ctx: CtxMock, id: number, datos: { nombre: string; documento: string }, _s: CamposSeguros): Promise<Jugador> {
  const j = buscar(id);
  Object.assign(j, datos);
  return { ...j };
}

export async function desactivarJugador(_ctx: CtxMock, id: number, _s: CamposSeguros): Promise<null> {
  const j = buscar(id);
  j.activo = false;
  j.estado = 'Inactivo';
  return null;
}

export async function solicitarPausa(ctx: CtxMock, _s: CamposSeguros): Promise<Suspension> {
  const j = buscar(mockJugadorDeUsuario[ctx.sesion?.usuarioId ?? -1] ?? -1);
  const inicio = new Date();
  const s: Suspension = { id: siguienteId(mockSuspensiones), jugadorId: j.id, jugadorCodigo: j.codigo, jugadorNombre: j.nombre,
    motivo: 'pausa_voluntaria', inicio: inicio.toISOString(), fin: new Date(inicio.getTime() + 24 * 3600_000).toISOString(), levantadaEn: null, activa: true };
  mockSuspensiones.push(s);
  if (j.estado === 'Activo') { j.estado = 'Suspendido'; j.suspendidoHasta = s.fin; }
  return { ...s };
}

export async function listarSuspensiones(_ctx: CtxMock, soloActivas: boolean): Promise<Suspension[]> {
  return mockSuspensiones.filter((s) => !soloActivas || s.activa).map((s) => ({ ...s }));
}

export async function listarInvestigaciones(_ctx: CtxMock, soloAbiertas: boolean): Promise<Investigacion[]> {
  return mockInvestigaciones.filter((i) => !soloAbiertas || i.cerradaEn === null).map((i) => ({ ...i }));
}

export async function cerrarInvestigacion(_ctx: CtxMock, id: number, resolucion: string, _s: CamposSeguros): Promise<null> {
  const inv = mockInvestigaciones.find((i) => i.id === id);
  if (!inv || inv.cerradaEn) throw new ErrorCasino('CA305', 'La investigación no existe o ya está cerrada');
  inv.cerradaEn = new Date().toISOString();
  inv.resolucion = resolucion;
  const j = buscar(inv.jugadorId);
  if (j.estado === 'Investigación') j.estado = 'Activo';
  return null;
}

export async function registrarAbono(_ctx: CtxMock, empleadoId: number, monto: Dinero, _s: CamposSeguros): Promise<{ deudaRestante: Dinero }> {
  mockAbonos.push({ empleadoId, monto });
  return { deudaRestante: dinero(Math.max(0, 500000 - mockAbonos.filter((a) => a.empleadoId === empleadoId).reduce((s, a) => s + centavos(a.monto), 0))) };
}

export async function obtenerUmbral(_ctx: CtxMock): Promise<{ umbralPerdidaDiaria: Dinero }> {
  return { ...mockConfiguracion };
}

export async function actualizarUmbral(_ctx: CtxMock, monto: Dinero, _s: CamposSeguros): Promise<null> {
  mockConfiguracion.umbralPerdidaDiaria = Number(monto).toFixed(2);
  return null;
}

export async function registrarConsignacion(_ctx: CtxMock, jugadorId: number, monto: Dinero, _s: CamposSeguros): Promise<Movimiento> {
  moverSaldoMock(jugadorId, 'consignacion', Number(monto).toFixed(2));
  const { jugadorId: _j, ...m } = mockMovimientos[mockMovimientos.length - 1];
  return m;
}

export async function registrarRetiro(_ctx: CtxMock, jugadorId: number, monto: Dinero, _s: CamposSeguros): Promise<Movimiento> {
  if (buscar(jugadorId).estado === 'Investigación') throw new ErrorCasino('CA303', 'El jugador está en investigación');
  moverSaldoMock(jugadorId, 'retiro', Number(monto).toFixed(2));
  const { jugadorId: _j, ...m } = mockMovimientos[mockMovimientos.length - 1];
  return m;
}
