'use server';
import { z } from 'zod';
import type { Asignacion, Jornada, Mesa, Turno } from '@/lib/contrato';
import { camel, crearAccion, ErrorCasino, zDinero, zId, zSeguro, type Ctx } from '@/server/accion';
import * as mock from '@/server/mocks/mesas';

const zMesa = z.object({ codigo: z.string().trim().min(1).max(20), juegoId: zId, montoMinimo: zDinero, montoMaximo: zDinero });
const zConcepto = z.enum(['Genera ganancias', 'Genera pérdidas', 'Sospecha de fraude', 'Comportamiento neutro']);
const zFecha = z.iso.datetime({ offset: true });

async function leerMesa(q: Ctx['q'], id: number): Promise<Mesa> {
  const [f] = await q('SELECT * FROM casino.v_mesas WHERE id = $1', [id]);
  if (!f) throw new ErrorCasino('CA104', 'Mesa no encontrada');
  return camel<Mesa>(f);
}
async function leerTurno(q: Ctx['q'], id: number): Promise<Turno> {
  const [f] = await q('SELECT * FROM casino.v_turnos WHERE id = $1', [id]);
  if (!f) throw new ErrorCasino('CA105', 'Turno no encontrado');
  return camel<Turno>(f);
}
async function leerAsignacion(q: Ctx['q'], id: number): Promise<Asignacion> {
  const [f] = await q('SELECT * FROM casino.v_asignaciones WHERE id = $1', [id]);
  if (!f) throw new ErrorCasino('CA106', 'Asignación no encontrada');
  return camel<Asignacion>(f);
}
export const listarMesas = crearAccion(
  { roles: ['administrador', 'crupier', 'supervisor'], seguro: false, args: z.tuple([]), mock: mock.listarMesas },
  async ({ q }): Promise<Mesa[]> => (await q('SELECT * FROM casino.v_mesas ORDER BY codigo')).map(f => camel<Mesa>(f)),
);
export const crearMesa = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zMesa, zSeguro]), mock: mock.crearMesa },
  async ({ q }, d) => {
    const [f] = await q<{ id: number }>('SELECT casino.fn_crear_mesa($1,$2,$3,$4) AS id', [d.codigo, d.juegoId, d.montoMinimo, d.montoMaximo]);
    return leerMesa(q, f.id);
  },
);
export const actualizarMesa = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zMesa, zSeguro]), mock: mock.actualizarMesa },
  async ({ q }, id, d) => {
    await q('SELECT casino.fn_actualizar_mesa($1,$2,$3,$4,$5)', [id, d.codigo, d.juegoId, d.montoMinimo, d.montoMaximo]);
    return leerMesa(q, id);
  },
);
export const desactivarMesa = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.desactivarMesa },
  async ({ q }, id) => { await q('SELECT casino.fn_desactivar_mesa($1)', [id]); return null; },
);
export const listarJornadas = crearAccion(
  { roles: ['administrador', 'supervisor'], seguro: false, args: z.tuple([]), mock: mock.listarJornadas },
  async ({ q }): Promise<Jornada[]> => (await q('SELECT * FROM casino.v_jornadas ORDER BY fecha DESC')).map(f => camel<Jornada>(f)),
);
export const crearJornada = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([z.iso.date(), zSeguro]), mock: mock.crearJornada },
  async ({ q }, fecha) => {
    const [f] = await q<{ id: number }>('SELECT casino.fn_crear_jornada($1::date) AS id', [fecha]);
    const [jornada] = await q('SELECT * FROM casino.v_jornadas WHERE id = $1', [f.id]);
    return camel<Jornada>(jornada);
  },
);
export const listarTurnos = crearAccion(
  { roles: ['administrador', 'supervisor'], seguro: false, args: z.tuple([zId]), mock: mock.listarTurnos },
  async ({ q }, jornadaId): Promise<Turno[]> => (await q('SELECT * FROM casino.v_turnos WHERE jornada_id = $1 ORDER BY numero', [jornadaId])).map(f => camel<Turno>(f)),
);
export const crearTurno = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, z.object({ inicio: zFecha, fin: zFecha }), zSeguro]), mock: mock.crearTurno },
  async ({ q }, jornadaId, d) => {
    const [f] = await q<{ id: number }>('SELECT casino.fn_crear_turno($1,$2::timestamptz,$3::timestamptz) AS id', [jornadaId, d.inicio, d.fin]);
    return leerTurno(q, f.id);
  },
);
export const eliminarTurno = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.eliminarTurno },
  async ({ q }, id) => { await q('SELECT casino.fn_eliminar_turno($1)', [id]); return null; },
);
export const listarAsignaciones = crearAccion(
  { roles: ['administrador', 'supervisor'], seguro: false, args: z.tuple([zId]), mock: mock.listarAsignaciones },
  async ({ q }, jornadaId): Promise<Asignacion[]> =>
    (await q('SELECT * FROM casino.v_asignaciones WHERE jornada_id = $1 ORDER BY turno_numero, mesa_codigo', [jornadaId])).map(f => camel<Asignacion>(f)),
);
export const crearAsignacion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([z.object({ turnoId: zId, mesaId: zId, crupierId: zId, supervisorId: zId }), zSeguro]), mock: mock.crearAsignacion },
  async ({ q }, d) => {
    const [f] = await q<{ id: number }>('SELECT casino.fn_crear_asignacion($1,$2,$3,$4) AS id', [d.turnoId, d.mesaId, d.crupierId, d.supervisorId]);
    return leerAsignacion(q, f.id);
  },
);
export const eliminarAsignacion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.eliminarAsignacion },
  async ({ q }, id) => { await q('SELECT casino.fn_eliminar_asignacion($1)', [id]); return null; },
);
export const misTurnosSupervisor = crearAccion(
  { roles: ['supervisor'], seguro: false, args: z.tuple([]), mock: mock.misTurnosSupervisor },
  async ({ q }): Promise<Asignacion[]> => (await q('SELECT * FROM casino.v_mis_turnos_supervisor ORDER BY inicio, mesa_codigo')).map(f => camel<Asignacion>(f)),
);
export const emitirConcepto = crearAccion(
  { roles: ['supervisor'], seguro: true, args: z.tuple([zId, zConcepto, z.string().trim().max(500).nullable(), zSeguro]), mock: mock.emitirConcepto },
  async ({ q }, id, concepto, observacion) => {
    await q('SELECT casino.fn_emitir_concepto($1,$2,$3)', [id, concepto, observacion]);
    return leerAsignacion(q, id);
  },
);
