'use server';
// Acciones de apuestas y opciones de apuesta (André).
import { z } from 'zod';
import type { Apuesta, JugadorParaApuesta, OpcionApuesta } from '@/lib/contrato';
import { camel, crearAccion, ErrorCasino, zDinero, zFactor, zId, zSeguro, type Ctx } from '@/server/accion';
import * as mock from '@/server/mocks/apuestas';

const TODOS = ['administrador', 'crupier', 'supervisor', 'jugador'] as const;
const zDatosOpcion = z.object({ nombre: z.string().trim().min(1).max(60), factorPago: zFactor });
const zDatosApuesta = z.object({ rondaId: zId, jugadorId: zId, opcionId: zId, monto: zDinero });

async function leerOpcion(q: Ctx['q'], id: number): Promise<OpcionApuesta> {
  const [f] = await q('SELECT id, juego_id, nombre, factor_pago, activa FROM casino.v_opciones WHERE id = $1', [id]);
  if (!f) throw new ErrorCasino('CA215', 'La opción de apuesta no existe');
  return camel<OpcionApuesta>(f);
}

async function leerApuesta(q: Ctx['q'], id: number): Promise<Apuesta> {
  const [f] = await q('SELECT * FROM casino.v_apuestas WHERE id = $1', [id]);
  if (!f) throw new ErrorCasino('CA215', 'La apuesta no existe');
  return camel<Apuesta>(f);
}

export const listarOpciones = crearAccion(
  { roles: [...TODOS], seguro: false, args: z.tuple([zId]), mock: mock.listarOpciones },
  async ({ q }, juegoId) =>
    (await q('SELECT id, juego_id, nombre, factor_pago, activa FROM casino.v_opciones WHERE juego_id = $1 ORDER BY id', [juegoId]))
      .map((f) => camel<OpcionApuesta>(f)),
);

export const crearOpcion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDatosOpcion, zSeguro]), mock: mock.crearOpcion },
  async ({ q }, juegoId, datos) => {
    const [{ id }] = await q<{ id: number }>('SELECT casino.fn_crear_opcion($1, $2, $3) AS id', [juegoId, datos.nombre, datos.factorPago]);
    return leerOpcion(q, id);
  },
);

export const actualizarOpcion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDatosOpcion, zSeguro]), mock: mock.actualizarOpcion },
  async ({ q }, id, datos) => {
    await q('SELECT casino.fn_actualizar_opcion($1, $2, $3)', [id, datos.nombre, datos.factorPago]);
    return leerOpcion(q, id);
  },
);

export const desactivarOpcion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.desactivarOpcion },
  async ({ q }, id) => {
    await q('SELECT casino.fn_desactivar_opcion($1)', [id]);
    return null;
  },
);

export const buscarJugadorParaApuesta = crearAccion(
  { roles: ['crupier'], seguro: false, args: z.tuple([z.string().trim().min(1).max(20)]), mock: mock.buscarJugadorParaApuesta },
  async ({ q }, codigo) => {
    const [f] = await q('SELECT * FROM casino.v_jugador_para_apuesta WHERE codigo = $1', [codigo.toUpperCase()]);
    if (!f) throw new ErrorCasino('CA012', 'El jugador no existe');
    return camel<JugadorParaApuesta>(f);
  },
);

export const listarApuestas = crearAccion(
  { roles: ['crupier', 'supervisor', 'administrador'], seguro: false, args: z.tuple([zId]), mock: mock.listarApuestas },
  async ({ q }, rondaId) =>
    (await q('SELECT * FROM casino.v_apuestas WHERE ronda_id = $1 ORDER BY id', [rondaId])).map((f) => camel<Apuesta>(f)),
);

export const registrarApuesta = crearAccion(
  { roles: ['crupier'], seguro: true, args: z.tuple([zDatosApuesta, zSeguro]), mock: mock.registrarApuesta },
  async ({ q }, d) => {
    const [{ id }] = await q<{ id: number }>('SELECT casino.fn_registrar_apuesta($1, $2, $3, $4) AS id', [d.rondaId, d.jugadorId, d.opcionId, d.monto]);
    return leerApuesta(q, id);
  },
);

export const registrarApuestaResuelta = crearAccion(
  { roles: ['crupier'], seguro: true, args: z.tuple([zDatosApuesta.extend({ ganada: z.boolean() }), zSeguro]), mock: mock.registrarApuestaResuelta },
  async ({ q }, d) => {
    const [{ id }] = await q<{ id: number }>(
      'SELECT casino.fn_registrar_apuesta_resuelta($1, $2, $3, $4, $5) AS id',
      [d.rondaId, d.jugadorId, d.opcionId, d.monto, d.ganada],
    );
    return leerApuesta(q, id);
  },
);

export const anularApuesta = crearAccion(
  { roles: ['crupier'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.anularApuesta },
  async ({ q }, apuestaId) => {
    await q('SELECT casino.fn_anular_apuesta($1)', [apuestaId]);
    return null;
  },
);
