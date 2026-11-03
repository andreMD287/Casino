// Mock de mesas, jornadas, turnos y asignaciones (MODO_MOCK=1). Creado por André en la fase 0; desde ahí es de Andrés.
import type { Asignacion, CamposSeguros, Concepto, Dinero, FechaISO, Jornada, Mesa, Turno } from '@/lib/contrato';
import type { CtxMock } from '@/server/accion';
import { ErrorCasino } from '@/server/errores';
import {
  mockApuestas, mockAsignaciones, mockEmpleados, mockJornadas, mockJuegos, mockMesas, mockRondas, mockTurnos, siguienteId,
} from '@/server/mocks/datos';

type DatosMesa = { codigo: string; juegoId: number; montoMinimo: Dinero; montoMaximo: Dinero };

function armarMesa(id: number, datos: DatosMesa, activa = true): Mesa {
  const j = mockJuegos.find((x) => x.id === datos.juegoId);
  if (!j) throw new ErrorCasino('CA000', 'El juego no existe');
  const codigo = datos.codigo.trim();
  const minimo = Number(datos.montoMinimo);
  const maximo = Number(datos.montoMaximo);
  if (!codigo || !Number.isFinite(minimo) || !Number.isFinite(maximo) || minimo <= 0 || maximo < minimo) {
    throw new ErrorCasino('CA103', 'El mínimo de la mesa debe ser positivo y no superar el máximo');
  }
  return { id, codigo, juegoId: j.id, juego: j.nombre, registroDetallado: j.registroDetallado,
    montoMinimo: minimo.toFixed(2), montoMaximo: maximo.toFixed(2), activa };
}


export async function listarMesas(_ctx: CtxMock): Promise<Mesa[]> {
  return mockMesas.map((m) => ({ ...m }));
}

export async function crearMesa(_ctx: CtxMock, datos: DatosMesa, _s: CamposSeguros): Promise<Mesa> {
  const m = armarMesa(siguienteId(mockMesas), datos);
  if (mockMesas.some((x) => x.codigo === m.codigo)) throw new ErrorCasino('CA103', 'El código de la mesa ya existe');
  mockMesas.push(m);
  return { ...m };
}


export async function actualizarMesa(_ctx: CtxMock, id: number, datos: DatosMesa, _s: CamposSeguros): Promise<Mesa> {
  const i = mockMesas.findIndex((m) => m.id === id);
  if (i < 0) throw new ErrorCasino('CA104', 'Mesa no encontrada');
  const anterior = mockMesas[i];
  const nueva = armarMesa(id, datos, anterior.activa);
  if (mockMesas.some((x) => x.id !== id && x.codigo === nueva.codigo)) {
    throw new ErrorCasino('CA103', 'El código de la mesa ya existe');
  }
  if (anterior.juegoId !== nueva.juegoId &&
      (mockAsignaciones.some((a) => a.mesaId === id) || mockRondas.some((r) => r.mesaId === id))) {
    throw new ErrorCasino('CA124', 'No se puede cambiar el juego de una mesa con rondas o asignaciones');
  }
  mockMesas[i] = nueva;
  // En PostgreSQL las vistas calculan estos datos mediante JOIN; el mock conserva copias.
  for (const a of mockAsignaciones) {
    if (a.mesaId === id) { a.mesaCodigo = nueva.codigo; a.juego = nueva.juego; }
  }
  for (const a of mockApuestas) {
    if (a.mesaCodigo === anterior.codigo) a.mesaCodigo = nueva.codigo;
  }
  return { ...nueva };
}


export async function desactivarMesa(_ctx: CtxMock, id: number, _s: CamposSeguros): Promise<null> {
  const m = mockMesas.find((x) => x.id === id);
  if (!m) throw new ErrorCasino('CA104', 'Mesa no encontrada');
  if (mockRondas.some((r) => r.mesaId === id && r.estado === 'abierta') ||
      mockAsignaciones.some((a) => a.mesaId === id && Date.parse(a.fin) > Date.now())) {
    throw new ErrorCasino('CA125', 'No se puede desactivar una mesa con ronda abierta o asignaciones vigentes o futuras');
  }
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
  const i = mockTurnos.findIndex((t) => t.id === id);
  if (i < 0) throw new ErrorCasino('CA105', 'Turno no encontrado');
  const asigs = mockAsignaciones.filter((a) => a.turnoId === id);
  if (asigs.some((a) => a.concepto !== null) || mockRondas.some((r) => asigs.some((a) => a.id === r.asignacionId))) {
    throw new ErrorCasino('CA126', 'No se puede eliminar un turno con rondas o conceptos emitidos');
  }
  for (let j = mockAsignaciones.length - 1; j >= 0; j--) if (mockAsignaciones[j].turnoId === id) mockAsignaciones.splice(j, 1);
  mockTurnos.splice(i, 1);
  return null;
}

export async function listarAsignaciones(_ctx: CtxMock, jornadaId: number): Promise<Asignacion[]> {
  const turnos = mockTurnos.filter((t) => t.jornadaId === jornadaId).map((t) => t.id);
  return mockAsignaciones.filter((a) => turnos.includes(a.turnoId)).map((a) => ({ ...a }));
}

export async function crearAsignacion(_ctx: CtxMock, datos: { turnoId: number; mesaId: number; crupierId: number; supervisorId: number }, _s: CamposSeguros): Promise<Asignacion> {
  const t = mockTurnos.find((x) => x.id === datos.turnoId);
  const m = mockMesas.find((x) => x.id === datos.mesaId);
  if (!t || !m || !m.activa) throw new ErrorCasino('CA112', 'El turno no existe o la mesa está inactiva');
  const c = mockEmpleados.find((x) => x.id === datos.crupierId && x.cargo === 'crupier' && x.activo);
  if (!c) throw new ErrorCasino('CA113', 'Se requiere un crupier activo');
  const s = mockEmpleados.find((x) => x.id === datos.supervisorId && x.cargo === 'supervisor' && x.activo);
  if (!s) throw new ErrorCasino('CA114', 'Se requiere un supervisor activo');
  if (!c.competencias.some((x) => x.juegoId === m.juegoId) || !s.competencias.some((x) => x.juegoId === m.juegoId)) {
    throw new ErrorCasino('CA115', 'El crupier y el supervisor deben conocer el juego de la mesa');
  }
  if (mockAsignaciones.some((a) => a.turnoId === t.id && a.mesaId === m.id)) {
    throw new ErrorCasino('CA116', 'La mesa ya tiene crupier en este turno');
  }
  if (mockAsignaciones.some((a) => a.turnoId === t.id && a.crupierId === c.id)) {
    throw new ErrorCasino('CA117', 'El crupier ya atiende otra mesa en este turno');
  }
  if (mockAsignaciones.some((a) => a.crupierId === c.id && a.mesaId === m.id &&
      mockTurnos.some((otro) => otro.id === a.turnoId && otro.jornadaId === t.jornadaId))) {
    throw new ErrorCasino('CA118', 'El crupier ya estuvo en esta mesa hoy; debe rotar');
  }
  const a: Asignacion = { id: siguienteId(mockAsignaciones), turnoId: t.id, turnoNumero: t.numero, inicio: t.inicio, fin: t.fin,
    mesaId: m.id, mesaCodigo: m.codigo, juego: m.juego, crupierId: c.id, crupierNombre: c.nombre, supervisorId: s.id,
    supervisorNombre: s.nombre, concepto: null, observacion: null };
  mockAsignaciones.push(a);
  return { ...a };
}


export async function eliminarAsignacion(_ctx: CtxMock, id: number, _s: CamposSeguros): Promise<null> {
  const i = mockAsignaciones.findIndex((a) => a.id === id);
  if (i < 0) throw new ErrorCasino('CA106', 'Asignación no encontrada');
  if (mockAsignaciones[i].concepto !== null || mockRondas.some((r) => r.asignacionId === id)) {
    throw new ErrorCasino('CA126', 'No se puede eliminar una asignación con rondas o concepto emitido');
  }
  mockAsignaciones.splice(i, 1);
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
