// Mock de apuestas y opciones (MODO_MOCK=1).
import type { Apuesta, CamposSeguros, Dinero, JugadorParaApuesta, OpcionApuesta } from '@/lib/contrato';
import type { CtxMock } from '@/server/accion';
import { ErrorCasino } from '@/server/errores';
import {
  centavos, dinero, mockApuestas, mockAsignaciones, mockEmpleados, mockJugadores, mockMesas, mockOpciones, mockRondas,
  moverSaldoMock, nuevaApuestaId, siguienteId,
} from '@/server/mocks/datos';

export async function listarOpciones(_ctx: CtxMock, juegoId: number): Promise<OpcionApuesta[]> {
  return mockOpciones.filter((o) => o.juegoId === juegoId).map((o) => ({ ...o }));
}

export async function crearOpcion(_ctx: CtxMock, juegoId: number, datos: { nombre: string; factorPago: string }, _s: CamposSeguros): Promise<OpcionApuesta> {
  if (mockOpciones.some((o) => o.juegoId === juegoId && o.nombre === datos.nombre)) throw new ErrorCasino('CA214', 'Ya existe una opción con ese nombre en el juego');
  const o = { id: siguienteId(mockOpciones), juegoId, nombre: datos.nombre, factorPago: Number(datos.factorPago).toFixed(2), activa: true };
  mockOpciones.push(o);
  return { ...o };
}

export async function actualizarOpcion(_ctx: CtxMock, id: number, datos: { nombre: string; factorPago: string }, _s: CamposSeguros): Promise<OpcionApuesta> {
  const o = mockOpciones.find((x) => x.id === id);
  if (!o) throw new ErrorCasino('CA215', 'La opción de apuesta no existe');
  const factor = Number(datos.factorPago).toFixed(2);
  if (factor !== o.factorPago && mockApuestas.some((a) => a.opcionId === id && a.estado === 'pendiente')) {
    throw new ErrorCasino('CA213', 'No se puede cambiar el factor: la opción tiene apuestas pendientes');
  }
  o.nombre = datos.nombre;
  o.factorPago = factor;
  return { ...o };
}

export async function desactivarOpcion(_ctx: CtxMock, id: number, _s: CamposSeguros): Promise<null> {
  const o = mockOpciones.find((x) => x.id === id);
  if (!o) throw new ErrorCasino('CA215', 'La opción de apuesta no existe');
  o.activa = false;
  return null;
}

export async function buscarJugadorParaApuesta(_ctx: CtxMock, codigo: string): Promise<JugadorParaApuesta> {
  const j = mockJugadores.find((x) => x.codigo === codigo.trim().toUpperCase());
  if (!j) throw new ErrorCasino('CA012', 'El jugador no existe');
  const motivo = j.estado === 'Activo' ? null
    : j.estado === 'Suspendido' ? `El jugador está suspendido hasta ${j.suspendidoHasta}`
    : j.estado === 'Investigación' ? 'El jugador está en investigación' : 'El jugador está inactivo';
  return { jugadorId: j.id, codigo: j.codigo, nombre: j.nombre, saldo: j.saldo, puedeApostar: motivo === null, motivo };
}

export async function listarApuestas(_ctx: CtxMock, rondaId: number): Promise<Apuesta[]> {
  return mockApuestas.filter((a) => a.rondaId === rondaId).map((a) => ({ ...a }));
}

function validar(ctx: CtxMock, datos: { rondaId: number; jugadorId: number; opcionId: number; monto: Dinero }, detallado: boolean) {
  const r = mockRondas.find((x) => x.id === datos.rondaId);
  if (!r) throw new ErrorCasino('CA215', 'La ronda no existe');
  const asig = mockAsignaciones.find((a) => a.id === r.asignacionId)!;
  if (asig.crupierId !== mockEmpleados.find((e) => e.usuario === ctx.sesion?.usuario)?.id) throw new ErrorCasino('CA207', 'No eres el crupier asignado a esta ronda');
  const mesa = mockMesas.find((m) => m.id === r.mesaId)!;
  if (detallado && !mesa.registroDetallado) throw new ErrorCasino('CA209', 'Este juego no tiene registro detallado: registra la apuesta con su resultado');
  if (!detallado && mesa.registroDetallado) throw new ErrorCasino('CA210', 'Este juego tiene registro detallado: registra la apuesta antes del resultado');
  if (r.estado !== 'abierta') throw new ErrorCasino('CA203', 'La ronda no está abierta');
  const o = mockOpciones.find((x) => x.id === datos.opcionId);
  if (!o || !o.activa || o.juegoId !== mesa.juegoId) throw new ErrorCasino('CA204', 'La opción de apuesta no está activa o no es del juego de esta mesa');
  if (centavos(datos.monto) < centavos(mesa.montoMinimo) || centavos(datos.monto) > centavos(mesa.montoMaximo)) {
    throw new ErrorCasino('CA205', `El monto debe estar entre ${mesa.montoMinimo} y ${mesa.montoMaximo} en esta mesa`);
  }
  const j = mockJugadores.find((x) => x.id === datos.jugadorId);
  if (!j) throw new ErrorCasino('CA012', 'El jugador no existe');
  if (j.estado === 'Inactivo') throw new ErrorCasino('CA301', 'El jugador está inactivo');
  if (j.estado === 'Suspendido') throw new ErrorCasino('CA302', `El jugador está suspendido hasta ${j.suspendidoHasta}`);
  if (j.estado === 'Investigación') throw new ErrorCasino('CA303', 'El jugador está en investigación');
  return { r, mesa, o, j };
}

export async function registrarApuesta(ctx: CtxMock, datos: { rondaId: number; jugadorId: number; opcionId: number; monto: Dinero }, _s: CamposSeguros): Promise<Apuesta> {
  const { r, mesa, o, j } = validar(ctx, datos, true);
  const id = nuevaApuestaId();
  moverSaldoMock(j.id, 'apuesta', dinero(centavos(datos.monto)), id);
  const ap: Apuesta = { id, rondaId: r.id, mesaCodigo: mesa.codigo, rondaNumero: r.numero, jugadorId: j.id, jugadorCodigo: j.codigo,
    jugadorNombre: j.nombre, opcionId: o.id, opcion: o.nombre, monto: dinero(centavos(datos.monto)), factorPago: o.factorPago,
    estado: 'pendiente', premio: null, creadaEn: new Date().toISOString(), liquidadaEn: null };
  mockApuestas.push(ap);
  return { ...ap };
}

export async function registrarApuestaResuelta(ctx: CtxMock, datos: { rondaId: number; jugadorId: number; opcionId: number; monto: Dinero; ganada: boolean }, _s: CamposSeguros): Promise<Apuesta> {
  const { r, mesa, o, j } = validar(ctx, datos, false);
  const id = nuevaApuestaId();
  const monto = dinero(centavos(datos.monto));
  const premio = datos.ganada ? dinero(Math.round(centavos(monto) * Number(o.factorPago))) : null;
  moverSaldoMock(j.id, 'apuesta', monto, id);
  if (premio) {
    moverSaldoMock(j.id, 'devolucion', monto, id);
    moverSaldoMock(j.id, 'premio', premio, id);
  }
  const ahora = new Date().toISOString();
  const ap: Apuesta = { id, rondaId: r.id, mesaCodigo: mesa.codigo, rondaNumero: r.numero, jugadorId: j.id, jugadorCodigo: j.codigo,
    jugadorNombre: j.nombre, opcionId: o.id, opcion: o.nombre, monto, factorPago: o.factorPago,
    estado: datos.ganada ? 'ganada' : 'perdida', premio, creadaEn: ahora, liquidadaEn: ahora };
  mockApuestas.push(ap);
  return { ...ap };
}

export async function anularApuesta(_ctx: CtxMock, apuestaId: number, _s: CamposSeguros): Promise<null> {
  const ap = mockApuestas.find((a) => a.id === apuestaId);
  if (!ap) throw new ErrorCasino('CA215', 'La apuesta no existe');
  const r = mockRondas.find((x) => x.id === ap.rondaId)!;
  if (ap.estado !== 'pendiente' || r.estado !== 'abierta') throw new ErrorCasino('CA211', 'Solo se puede anular una apuesta pendiente de una ronda abierta');
  ap.estado = 'anulada';
  moverSaldoMock(ap.jugadorId, 'devolucion', ap.monto, ap.id);
  return null;
}
