'use server';
// Acciones de rondas (André). Validan formato con zod y llaman las funciones fn_* de la BD.
import { z } from 'zod';
import type { FilaReporte, MesaCrupier, ResumenLiquidacion, Ronda } from '@/lib/contrato';
import { camel, crearAccion, ErrorCasino, zId, zSeguro, type Ctx } from '@/server/accion';
import * as mock from '@/server/mocks/rondas';

const COLUMNAS_RONDA = 'id, mesa_id, numero, inicio, cierre, estado, resultado';

async function leerRonda(q: Ctx['q'], rondaId: number): Promise<Ronda> {
  const [fila] = await q(`SELECT ${COLUMNAS_RONDA} FROM casino.v_rondas WHERE id = $1`, [rondaId]);
  if (!fila) throw new ErrorCasino('CA215', 'La ronda no existe');
  return camel<Ronda>(fila);
}

export const misMesasActuales = crearAccion(
  { roles: ['crupier'], seguro: false, args: z.tuple([]), mock: mock.misMesasActuales },
  async ({ q }): Promise<MesaCrupier[]> => {
    const filas = await q('SELECT * FROM casino.v_mis_mesas_actuales ORDER BY mesa_codigo');
    const salida: MesaCrupier[] = [];
    for (const f of filas) {
      salida.push({
        asignacionId: f.asignacion_id as number,
        mesa: {
          id: f.mesa_id as number, codigo: f.mesa_codigo as string, juegoId: f.juego_id as number, juego: f.juego as string,
          registroDetallado: f.registro_detallado as boolean, montoMinimo: f.monto_minimo as string,
          montoMaximo: f.monto_maximo as string, activa: f.mesa_activa as boolean,
        },
        inicioTurno: f.inicio_turno as string,
        finTurno: f.fin_turno as string,
        rondaAbierta: f.ronda_abierta_id ? await leerRonda(q, f.ronda_abierta_id as number) : null,
      });
    }
    return salida;
  },
);

export const listarRondas = crearAccion(
  { roles: ['crupier', 'supervisor', 'administrador'], seguro: false, args: z.tuple([zId]), mock: mock.listarRondas },
  async ({ q }, mesaId) =>
    (await q(`SELECT ${COLUMNAS_RONDA} FROM casino.v_rondas WHERE mesa_id = $1 ORDER BY numero DESC`, [mesaId])).map((f) => camel<Ronda>(f)),
);

export const obtenerRonda = crearAccion(
  { roles: ['crupier', 'supervisor', 'administrador'], seguro: false, args: z.tuple([zId]), mock: mock.obtenerRonda },
  async ({ q }, rondaId) => leerRonda(q, rondaId),
);

export const abrirRonda = crearAccion(
  { roles: ['crupier'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.abrirRonda },
  async ({ q }, mesaId) => {
    const [{ id }] = await q<{ id: number }>('SELECT casino.fn_abrir_ronda($1) AS id', [mesaId]);
    return leerRonda(q, id);
  },
);

export const cerrarRonda = crearAccion(
  { roles: ['crupier'], seguro: true, args: z.tuple([zId, z.array(zId).max(50), zSeguro]), mock: mock.cerrarRonda },
  async ({ q }, rondaId, opcionesGanadoras): Promise<ResumenLiquidacion> => {
    const [f] = await q('SELECT * FROM casino.fn_cerrar_ronda($1, $2::bigint[])', [rondaId, opcionesGanadoras]);
    return camel<ResumenLiquidacion>(f);
  },
);

export const anularRonda = crearAccion(
  { roles: ['crupier', 'administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.anularRonda },
  async ({ q }, rondaId) => {
    await q('SELECT casino.fn_anular_ronda($1)', [rondaId]);
    return null;
  },
);

export const reporteMesaTurno = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([zId]), mock: mock.reporteMesaTurno },
  async ({ q }, jornadaId) =>
    (await q(
      `SELECT fecha, turno_numero, mesa_codigo, crupier, supervisor, total_apostado, total_premios, resultado_nominal, concepto
       FROM casino.v_reporte_mesa_turno WHERE jornada_id = $1 ORDER BY turno_numero, mesa_codigo`,
      [jornadaId],
    )).map((f) => camel<FilaReporte>(f)),
);
