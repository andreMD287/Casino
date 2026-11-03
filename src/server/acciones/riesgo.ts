'use server';
import { z } from 'zod';
import type { Apuesta, Historial, Investigacion, Jugador, Movimiento, Suspension } from '@/lib/contrato';
import { camel, crearAccion, ErrorCasino, zDinero, zId, zSeguro, type Ctx } from '@/server/accion';
import * as mock from '@/server/mocks/riesgo';

const zDatosJugador = z.object({ nombre: z.string().trim().min(3).max(100), documento: z.string().trim().min(3).max(20) });
async function leerJugador(q: Ctx['q'], id: number): Promise<Jugador> {
  const [f] = await q('SELECT * FROM casino.v_jugadores WHERE id = $1', [id]);
  if (!f) throw new ErrorCasino('CA301', 'Jugador no encontrado');
  return camel<Jugador>(f);
}
async function historial(q: Ctx['q'], jugadorId: number): Promise<Historial> {
  const jugador = await leerJugador(q, jugadorId);
  const apuestas = (await q('SELECT * FROM casino.v_historial_apuestas WHERE jugador_id = $1 ORDER BY creada_en DESC', [jugadorId])).map(f => camel<Apuesta>(f));
  const movimientos = (await q('SELECT id, tipo, monto, saldo_resultante, fecha, apuesta_id FROM casino.v_historial_movimientos WHERE jugador_id = $1 ORDER BY fecha DESC', [jugadorId])).map(f => camel<Movimiento>(f));
  const suspensiones = (await q('SELECT * FROM casino.v_suspensiones WHERE jugador_id = $1 ORDER BY inicio DESC', [jugadorId])).map(f => camel<Suspension>(f));
  const investigaciones = (await q('SELECT * FROM casino.v_investigaciones WHERE jugador_id = $1 ORDER BY abierta_en DESC', [jugadorId])).map(f => camel<Investigacion>(f));
  const [deuda] = await q<{ deuda: string }>('SELECT deuda FROM casino.v_deuda_empleado WHERE jugador_id = $1', [jugadorId]);
  return { jugador, apuestas, movimientos, suspensiones, investigaciones, deudaEmpleado: deuda?.deuda ?? null };
}
export const listarJugadores = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([z.string().trim().max(60).optional()]), mock: mock.listarJugadores },
  async ({ q }, filtro): Promise<Jugador[]> =>
    (await q(`SELECT * FROM casino.v_jugadores
      WHERE ($1::text IS NULL OR codigo ILIKE '%' || $1 || '%'
        OR nombre ILIKE '%' || $1 || '%' OR documento ILIKE '%' || $1 || '%') ORDER BY id`, [filtro || null])).map(f => camel<Jugador>(f)),
);
export const obtenerHistorial = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([zId]), mock: mock.obtenerHistorial },
  async ({ q }, id) => historial(q, id),
);
export const miHistorial = crearAccion(
  { roles: ['jugador'], seguro: false, args: z.tuple([]), mock: mock.miHistorial },
  async ({ q, sesion }) => {
    const [f] = await q<{ id: number }>('SELECT id FROM casino.v_jugadores WHERE usuario_id = $1', [sesion!.usuarioId]);
    if (!f) throw new ErrorCasino('CA301', 'Tu cuenta no tiene ficha de jugador');
    return historial(q, f.id);
  },
);
export const actualizarJugador = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDatosJugador, zSeguro]), mock: mock.actualizarJugador },
  async ({ q }, id, d) => { await q('SELECT casino.fn_actualizar_jugador($1,$2,$3)', [id, d.nombre, d.documento]); return leerJugador(q, id); },
);
export const desactivarJugador = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.desactivarJugador },
  async ({ q }, id) => { await q('SELECT casino.fn_desactivar_jugador($1)', [id]); return null; },
);
export const solicitarPausa = crearAccion(
  { roles: ['jugador'], seguro: true, args: z.tuple([zSeguro]), mock: mock.solicitarPausa },
  async ({ q }) => {
    const [f] = await q<{ id: number }>('SELECT casino.fn_solicitar_pausa() AS id');
    const [s] = await q('SELECT * FROM casino.v_suspensiones WHERE id = $1', [f.id]);
    return camel<Suspension>(s);
  },
);
export const listarSuspensiones = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([z.boolean()]), mock: mock.listarSuspensiones },
  async ({ q }, soloActivas): Promise<Suspension[]> =>
    (await q('SELECT * FROM casino.v_suspensiones WHERE ($1::boolean = false OR activa) ORDER BY inicio DESC', [soloActivas])).map(f => camel<Suspension>(f)),
);
export const listarInvestigaciones = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([z.boolean()]), mock: mock.listarInvestigaciones },
  async ({ q }, soloAbiertas): Promise<Investigacion[]> =>
    (await q('SELECT * FROM casino.v_investigaciones WHERE ($1::boolean = false OR cerrada_en IS NULL) ORDER BY abierta_en DESC', [soloAbiertas])).map(f => camel<Investigacion>(f)),
);
export const cerrarInvestigacion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, z.string().trim().min(3).max(500), zSeguro]), mock: mock.cerrarInvestigacion },
  async ({ q }, id, resolucion) => { await q('SELECT casino.fn_cerrar_investigacion($1,$2)', [id, resolucion]); return null; },
);
export const registrarAbono = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDinero, zSeguro]), mock: mock.registrarAbono },
  async ({ q }, id, monto) => {
    const [f] = await q<{ deuda_restante: string }>('SELECT casino.fn_registrar_abono($1,$2) AS deuda_restante', [id, monto]);
    return { deudaRestante: f.deuda_restante };
  },
);
export const obtenerUmbral = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([]), mock: mock.obtenerUmbral },
  async ({ q }) => {
    const [f] = await q<{ valor: string }>("SELECT valor FROM casino.v_configuracion WHERE clave = 'umbral_perdida_diaria'");
    if (!f) throw new ErrorCasino('CA309', 'El umbral de pérdida diaria aún no está configurado');
    return { umbralPerdidaDiaria: f.valor };
  },
);
export const actualizarUmbral = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zDinero, zSeguro]), mock: mock.actualizarUmbral },
  async ({ q }, monto) => { await q('SELECT casino.fn_actualizar_umbral($1)', [monto]); return null; },
);
// Opcionales: falta la implementación SQL y el acuerdo de habilitarlos.
const noDisponible = async (): Promise<never> => { throw new ErrorCasino('CA399', 'No disponible'); };
export const registrarConsignacion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDinero, zSeguro]), mock: mock.registrarConsignacion },
  async ({ q }, jugadorId, monto): Promise<Movimiento> => {
    const [r] = await q<{ id: number }>(
      'SELECT casino.fn_registrar_consignacion($1,$2) AS id',
      [jugadorId, monto],
    );
    if (!r) throw new Error('La consignacion no devolvio identificador de movimiento');
    const [movimiento] = await q(
      `SELECT id, tipo, monto, saldo_resultante, fecha, apuesta_id
       FROM casino.v_historial_movimientos
       WHERE id = $1 AND jugador_id = $2`,
      [r.id, jugadorId],
    );
    if (!movimiento) throw new Error('La consignacion no genero un movimiento consultable');
    return camel<Movimiento>(movimiento);
  },
);
export const registrarRetiro = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDinero, zSeguro]), mock: mock.registrarRetiro }, noDisponible,
);
