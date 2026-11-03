'use server';
import { z } from 'zod';
import type { Empleado, Juego } from '@/lib/contrato';
import { camel, crearAccion, ErrorCasino, zCredenciales, zDinero, zId, zSeguro, type Ctx } from '@/server/accion';
import * as mock from '@/server/mocks/personal';

const TODOS = ['administrador', 'crupier', 'supervisor', 'jugador'] as const;
const zCargo = z.enum(['administrador', 'crupier', 'supervisor']);
const zEmpleado = z.object({ nombre: z.string().trim().min(3).max(100), documento: z.string().trim().min(3).max(20), cargo: zCargo, salarioMensual: zDinero });

async function leerEmpleado(q: Ctx['q'], id: number): Promise<Empleado> {
  const [f] = await q('SELECT * FROM casino.v_empleados WHERE id = $1', [id]);
  if (!f) throw new ErrorCasino('CA102', 'Empleado no encontrado');
  return camel<Empleado>(f);
}

export const listarJuegos = crearAccion(
  { roles: [...TODOS], seguro: false, args: z.tuple([]), mock: mock.listarJuegos },
  async ({ q }): Promise<Juego[]> => (await q('SELECT * FROM casino.v_juegos ORDER BY nombre')).map(f => camel<Juego>(f)),
);
export const listarEmpleados = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([]), mock: mock.listarEmpleados },
  async ({ q }): Promise<Empleado[]> => (await q('SELECT * FROM casino.v_empleados ORDER BY id')).map(f => camel<Empleado>(f)),
);
export const crearEmpleado = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zEmpleado, zCredenciales, zSeguro]), mock: mock.crearEmpleado },
  async ({ q }, d, cred) => {
    const [f] = await q<{ id: number }>('SELECT casino.fn_crear_empleado($1,$2,$3,$4,$5,$6,$7) AS id',
      [d.nombre, d.documento, d.cargo, d.salarioMensual, cred.usuario, cred.salt, cred.verificador]);
    return leerEmpleado(q, f.id);
  },
);
export const actualizarEmpleado = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zEmpleado, zSeguro]), mock: mock.actualizarEmpleado },
  async ({ q }, id, d) => {
    await q('SELECT casino.fn_actualizar_empleado($1,$2,$3,$4,$5)', [id, d.nombre, d.documento, d.cargo, d.salarioMensual]);
    return leerEmpleado(q, id);
  },
);
export const desactivarEmpleado = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.desactivarEmpleado },
  async ({ q }, id) => { await q('SELECT casino.fn_desactivar_empleado($1)', [id]); return null; },
);
export const asignarCompetencia = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zId, zSeguro]), mock: mock.asignarCompetencia },
  async ({ q }, empleadoId, juegoId) => { await q('SELECT casino.fn_asignar_competencia($1,$2)', [empleadoId, juegoId]); return null; },
);
export const quitarCompetencia = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zId, zSeguro]), mock: mock.quitarCompetencia },
  async ({ q }, empleadoId, juegoId) => { await q('SELECT casino.fn_quitar_competencia($1,$2)', [empleadoId, juegoId]); return null; },
);
