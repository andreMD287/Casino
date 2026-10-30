// Mock de rondas (MODO_MOCK=1). Simula en memoria las mismas reglas que la BD.
import type { CamposSeguros, FilaReporte, MesaCrupier, ResumenLiquidacion, Ronda } from '@/lib/contrato';
import type { CtxMock } from '@/server/accion';
import { ErrorCasino } from '@/server/errores';
import {
  centavos, dinero, mockApuestas, mockAsignaciones, mockEmpleados, mockJornadas, mockMesas, mockOpciones, mockRondas, mockTurnos,
  moverSaldoMock, siguienteId,
} from '@/server/mocks/datos';

const sinAsignacion = ({ asignacionId: _a, ...r }: Ronda & { asignacionId: number }): Ronda => ({ ...r, resultado: [...r.resultado] });

function empleadoDe(ctx: CtxMock) {
  return mockEmpleados.find((e) => e.usuario === ctx.sesion?.usuario);
}

function asignacionVigente(mesaId: number) {
  const ahora = Date.now();
  return mockAsignaciones.find((a) => a.mesaId === mesaId && Date.parse(a.inicio) <= ahora && ahora < Date.parse(a.fin));
}

function rondaDelCrupier(ctx: CtxMock, rondaId: number) {
  const r = mockRondas.find((x) => x.id === rondaId);
  if (!r) throw new ErrorCasino('CA215', 'La ronda no existe');
  const a = mockAsignaciones.find((x) => x.id === r.asignacionId)!;
  if (ctx.sesion?.rol === 'crupier' && a.crupierId !== empleadoDe(ctx)?.id) {
    throw new ErrorCasino('CA207', 'No eres el crupier asignado a esta ronda');
  }
  return r;
}

export async function misMesasActuales(ctx: CtxMock): Promise<MesaCrupier[]> {
  const emp = empleadoDe(ctx);
  const ahora = Date.now();
  return mockAsignaciones
    .filter((a) => a.crupierId === emp?.id && Date.parse(a.inicio) <= ahora && ahora < Date.parse(a.fin))
    .map((a) => {
      const abierta = mockRondas.find((r) => r.mesaId === a.mesaId && r.estado === 'abierta');
      return { asignacionId: a.id, mesa: { ...mockMesas.find((m) => m.id === a.mesaId)! }, inicioTurno: a.inicio, finTurno: a.fin,
        rondaAbierta: abierta ? sinAsignacion(abierta) : null };
    });
}

export async function listarRondas(_ctx: CtxMock, mesaId: number): Promise<Ronda[]> {
  return mockRondas.filter((r) => r.mesaId === mesaId).sort((a, b) => b.numero - a.numero).map(sinAsignacion);
}

export async function obtenerRonda(_ctx: CtxMock, rondaId: number): Promise<Ronda> {
  const r = mockRondas.find((x) => x.id === rondaId);
  if (!r) throw new ErrorCasino('CA215', 'La ronda no existe');
  return sinAsignacion(r);
}

export async function abrirRonda(ctx: CtxMock, mesaId: number, _seguro: CamposSeguros): Promise<Ronda> {
  const a = asignacionVigente(mesaId);
  if (!a || a.crupierId !== empleadoDe(ctx)?.id) throw new ErrorCasino('CA207', 'No eres el crupier asignado a esta mesa en el turno actual');
  if (mockRondas.some((r) => r.mesaId === mesaId && r.estado === 'abierta')) throw new ErrorCasino('CA208', 'Ya hay una ronda abierta en esta mesa');
  const numero = Math.max(0, ...mockRondas.filter((r) => r.mesaId === mesaId).map((r) => r.numero)) + 1;
  const nueva = { id: siguienteId(mockRondas), mesaId, numero, inicio: new Date().toISOString(), cierre: null, estado: 'abierta' as const, resultado: [], asignacionId: a.id };
  mockRondas.push(nueva);
  return sinAsignacion(nueva);
}

export async function cerrarRonda(ctx: CtxMock, rondaId: number, opcionesGanadoras: number[], _seguro: CamposSeguros): Promise<ResumenLiquidacion> {
  const r = rondaDelCrupier(ctx, rondaId);
  if (r.estado !== 'abierta') throw new ErrorCasino('CA203', 'La ronda no está abierta');
  const mesa = mockMesas.find((m) => m.id === r.mesaId)!;
  if (mesa.registroDetallado && opcionesGanadoras.length === 0) throw new ErrorCasino('CA212', 'Debes indicar al menos una opción ganadora');
  if (!mesa.registroDetallado && opcionesGanadoras.length > 0) throw new ErrorCasino('CA216', 'Las rondas de juegos sin registro detallado se cierran sin resultado');
  const ahora = new Date().toISOString();
  for (const ap of mockApuestas.filter((x) => x.rondaId === rondaId && x.estado === 'pendiente')) {
    if (opcionesGanadoras.includes(ap.opcionId)) {
      ap.estado = 'ganada';
      ap.premio = dinero(Math.round(centavos(ap.monto) * Number(ap.factorPago)));
      moverSaldoMock(ap.jugadorId, 'devolucion', ap.monto, ap.id);
      moverSaldoMock(ap.jugadorId, 'premio', ap.premio, ap.id);
    } else {
      ap.estado = 'perdida';
    }
    ap.liquidadaEn = ahora;
  }
  r.resultado = opcionesGanadoras.map((id) => ({ opcionId: id, nombre: mockOpciones.find((o) => o.id === id)?.nombre ?? `Opción ${id}` }));
  r.estado = 'cerrada';
  r.cierre = ahora;
  const liquidadas = mockApuestas.filter((x) => x.rondaId === rondaId && (x.estado === 'ganada' || x.estado === 'perdida'));
  const apostado = liquidadas.reduce((s, x) => s + centavos(x.monto), 0);
  const premios = liquidadas.reduce((s, x) => s + centavos(x.premio ?? '0'), 0);
  const perdido = liquidadas.filter((x) => x.estado === 'perdida').reduce((s, x) => s + centavos(x.monto), 0);
  return { ganadas: liquidadas.filter((x) => x.estado === 'ganada').length, perdidas: liquidadas.filter((x) => x.estado === 'perdida').length,
    totalApostado: dinero(apostado), totalPremios: dinero(premios), resultadoCasino: dinero(perdido - premios) };
}

export async function anularRonda(ctx: CtxMock, rondaId: number, _seguro: CamposSeguros): Promise<null> {
  const r = rondaDelCrupier(ctx, rondaId);
  if (r.estado !== 'abierta') throw new ErrorCasino('CA203', 'Solo se puede anular una ronda abierta');
  for (const ap of mockApuestas.filter((x) => x.rondaId === rondaId && x.estado === 'pendiente')) {
    ap.estado = 'anulada';
    moverSaldoMock(ap.jugadorId, 'devolucion', ap.monto, ap.id);
  }
  r.estado = 'anulada';
  r.cierre = new Date().toISOString();
  return null;
}

export async function reporteMesaTurno(_ctx: CtxMock, jornadaId: number): Promise<FilaReporte[]> {
  const fecha = mockJornadas.find((j) => j.id === jornadaId)?.fecha ?? '';
  return mockAsignaciones
    .filter((a) => mockTurnos.find((t) => t.id === a.turnoId)?.jornadaId === jornadaId)
    .map((a) => {
      const rondas = mockRondas.filter((r) => r.asignacionId === a.id).map((r) => r.id);
      const aps = mockApuestas.filter((x) => rondas.includes(x.rondaId) && (x.estado === 'ganada' || x.estado === 'perdida'));
      const apostado = aps.reduce((s, x) => s + centavos(x.monto), 0);
      const premios = aps.reduce((s, x) => s + centavos(x.premio ?? '0'), 0);
      const perdido = aps.filter((x) => x.estado === 'perdida').reduce((s, x) => s + centavos(x.monto), 0);
      return { fecha, turnoNumero: a.turnoNumero, mesaCodigo: a.mesaCodigo, crupier: a.crupierNombre, supervisor: a.supervisorNombre,
        totalApostado: dinero(apostado), totalPremios: dinero(premios), resultadoNominal: dinero(perdido - premios), concepto: a.concepto };
    });
}
