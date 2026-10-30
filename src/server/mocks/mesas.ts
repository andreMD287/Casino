// Mock de mesas, jornadas, turnos y asignaciones (MODO_MOCK=1). Creado por André en la fase 0; desde ahí es de Andrés.
import type { Asignacion, CamposSeguros, Concepto, Dinero, FechaISO, Jornada, Mesa, Turno } from '@/lib/contrato';
import type { CtxMock } from '@/server/accion';
import { ErrorCasino } from '@/server/errores';
import {
  mockAsignaciones, mockEmpleados, mockJornadas, mockJuegos, mockMesas, mockRondas, mockTurnos, siguienteId,
} from '@/server/mocks/datos';

type DatosMesa = { codigo: string; juegoId: number; montoMinimo: Dinero; montoMaximo: Dinero };

function armarMesa(id: number, datos: DatosMesa, activa = true): Mesa {
  const j = mockJuegos.find((x) => x.id === datos.juegoId);
  if (!j) throw new ErrorCasino('CA103', 'El juego no existe');
  if (Number(datos.montoMinimo) <= 0 || Number(datos.montoMaximo) < Number(datos.montoMinimo)) {
    throw new ErrorCasino('CA104', 'El mínimo debe ser mayor que cero y no superar al máximo');
  }
  return { id, codigo: datos.codigo, juegoId: j.id, juego: j.nombre, registroDetallado: j.registroDetallado,
    montoMinimo: Number(datos.montoMinimo).toFixed(2), montoMaximo: Number(datos.montoMaximo).toFixed(2), activa };
}

export async function listarMesas(_ctx: CtxMock): Promise<Mesa[]> {
  return mockMesas.map((m) => ({ ...m }));
}

export async function crearMesa(_ctx: CtxMock, datos: DatosMesa, _s: CamposSeguros): Promise<Mesa> {
  if (mockMesas.some((m) => m.codigo === datos.codigo)) throw new ErrorCasino('CA105', 'Ya existe una mesa con ese código');
  const m = armarMesa(siguienteId(mockMesas), datos);
  mockMesas.push(m);
  return { ...m };
}

export async function actualizarMesa(_ctx: CtxMock, id: number, datos: DatosMesa, _s: CamposSeguros): Promise<Mesa> {
  const i = mockMesas.findIndex((m) => m.id === id);
  if (i < 0) throw new ErrorCasino('CA106', 'La mesa no existe');
  mockMesas[i] = armarMesa(id, datos, mockMesas[i].activa);
  return { ...mockMesas[i] };
}

export async function desactivarMesa(_ctx: CtxMock, id: number, _s: CamposSeguros): Promise<null> {
  const m = mockMesas.find((x) => x.id === id);
  if (!m) throw new ErrorCasino('CA106', 'La mesa no existe');
  m.activa = false;
  return null;
}

export async function listarJornadas(_ctx: CtxMock): Promise<Jornada[]> {
  return mockJornadas.map((j) => ({ ...j }));
}

export async function crearJornada(_ctx: CtxMock, fecha: string, _s: CamposSeguros): Promise<Jornada> {
  if (mockJornadas.some((j) => j.fecha === fecha)) throw new ErrorCasino('CA107', 'Ya existe una jornada para esa fecha');
  const j = { id: siguienteId(mockJornadas), fecha };
  mockJornadas.push(j);
  return { ...j };
}

export async function listarTurnos(_ctx: CtxMock, jornadaId: number): Promise<Turno[]> {
  return mockTurnos.filter((t) => t.jornadaId === jornadaId).map((t) => ({ ...t }));
}

export async function crearTurno(_ctx: CtxMock, jornadaId: number, datos: { inicio: FechaISO; fin: FechaISO }, _s: CamposSeguros): Promise<Turno> {
  const ini = Date.parse(datos.inicio);
  const fin = Date.parse(datos.fin);
  if (!(fin > ini) || fin - ini > 2 * 3600_000) throw new ErrorCasino('CA108', 'El turno debe durar más de 0 y máximo 2 horas');
  const delDia = mockTurnos.filter((t) => t.jornadaId === jornadaId);
  if (delDia.some((t) => ini < Date.parse(t.fin) && Date.parse(t.inicio) < fin)) throw new ErrorCasino('CA109', 'El turno se solapa con otro de la jornada');
  const t = { id: siguienteId(mockTurnos), jornadaId, numero: delDia.length + 1, inicio: datos.inicio, fin: datos.fin };
  mockTurnos.push(t);
  return { ...t };
}

export async function eliminarTurno(_ctx: CtxMock, id: number, _s: CamposSeguros): Promise<null> {
  const asigs = mockAsignaciones.filter((a) => a.turnoId === id).map((a) => a.id);
  if (mockRondas.some((r) => asigs.includes(r.asignacionId))) throw new ErrorCasino('CA110', 'No se puede eliminar: el turno tiene rondas');
  for (let i = mockAsignaciones.length - 1; i >= 0; i--) if (mockAsignaciones[i].turnoId === id) mockAsignaciones.splice(i, 1);
  const i = mockTurnos.findIndex((t) => t.id === id);
  if (i >= 0) mockTurnos.splice(i, 1);
  return null;
}

export async function listarAsignaciones(_ctx: CtxMock, jornadaId: number): Promise<Asignacion[]> {
  const turnos = mockTurnos.filter((t) => t.jornadaId === jornadaId).map((t) => t.id);
  return mockAsignaciones.filter((a) => turnos.includes(a.turnoId)).map((a) => ({ ...a }));
}

export async function crearAsignacion(_ctx: CtxMock, datos: { turnoId: number; mesaId: number; crupierId: number; supervisorId: number }, _s: CamposSeguros): Promise<Asignacion> {
  const t = mockTurnos.find((x) => x.id === datos.turnoId);
  const m = mockMesas.find((x) => x.id === datos.mesaId);
  const c = mockEmpleados.find((x) => x.id === datos.crupierId && x.cargo === 'crupier');
  const s = mockEmpleados.find((x) => x.id === datos.supervisorId && x.cargo === 'supervisor');
  if (!t || !m || !c || !s) throw new ErrorCasino('CA111', 'Turno, mesa, crupier o supervisor inválido');
  if (mockAsignaciones.some((a) => a.turnoId === t.id && a.mesaId === m.id)) throw new ErrorCasino('CA112', 'La mesa ya tiene crupier en ese turno');
  if (mockAsignaciones.some((a) => a.turnoId === t.id && a.crupierId === c.id)) throw new ErrorCasino('CA113', 'El crupier ya atiende otra mesa en ese turno');
  const a: Asignacion = { id: siguienteId(mockAsignaciones), turnoId: t.id, turnoNumero: t.numero, inicio: t.inicio, fin: t.fin,
    mesaId: m.id, mesaCodigo: m.codigo, juego: m.juego, crupierId: c.id, crupierNombre: c.nombre, supervisorId: s.id,
    supervisorNombre: s.nombre, concepto: null, observacion: null };
  mockAsignaciones.push(a);
  return { ...a };
}

export async function eliminarAsignacion(_ctx: CtxMock, id: number, _s: CamposSeguros): Promise<null> {
  if (mockRondas.some((r) => r.asignacionId === id)) throw new ErrorCasino('CA110', 'No se puede eliminar: la asignación tiene rondas');
  const i = mockAsignaciones.findIndex((a) => a.id === id);
  if (i >= 0) mockAsignaciones.splice(i, 1);
  return null;
}

export async function misTurnosSupervisor(ctx: CtxMock): Promise<Asignacion[]> {
  const emp = mockEmpleados.find((e) => e.usuario === ctx.sesion?.usuario);
  return mockAsignaciones.filter((a) => a.supervisorId === emp?.id).map((a) => ({ ...a }));
}

export async function emitirConcepto(ctx: CtxMock, asignacionId: number, concepto: Concepto, observacion: string | null, _s: CamposSeguros): Promise<Asignacion> {
  const a = mockAsignaciones.find((x) => x.id === asignacionId);
  const emp = mockEmpleados.find((e) => e.usuario === ctx.sesion?.usuario);
  if (!a || a.supervisorId !== emp?.id) throw new ErrorCasino('CA114', 'No eres el supervisor de esta asignación');
  if (Date.parse(a.fin) > Date.now()) throw new ErrorCasino('CA115', 'El concepto se emite cuando termina el turno');
  if (a.concepto) throw new ErrorCasino('CA116', 'Esta asignación ya tiene concepto');
  a.concepto = concepto;
  a.observacion = observacion;
  return { ...a };
}
