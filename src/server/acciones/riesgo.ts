'use server';
// Acciones de jugadores, riesgo e historial. Creado por André en la fase 0 con mocks; desde ahí es de Andrés.
// En modo real devuelven CA099 "Pendiente de implementar" hasta que Andrés las reemplace.
import { z } from 'zod';
import { crearAccion, ERR, zDinero, zId, zSeguro } from '@/server/accion';
import * as mock from '@/server/mocks/riesgo';

const pendiente = async (): Promise<never> => {
  throw ERR.pendiente();
};
const zDatosJugador = z.object({ nombre: z.string().trim().min(3).max(100), documento: z.string().trim().min(3).max(20) });

export const listarJugadores = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([z.string().trim().max(60).optional()]), mock: mock.listarJugadores }, pendiente);
export const obtenerHistorial = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([zId]), mock: mock.obtenerHistorial }, pendiente);
export const miHistorial = crearAccion(
  { roles: ['jugador'], seguro: false, args: z.tuple([]), mock: mock.miHistorial }, pendiente);
export const actualizarJugador = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDatosJugador, zSeguro]), mock: mock.actualizarJugador }, pendiente);
export const desactivarJugador = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.desactivarJugador }, pendiente);
export const solicitarPausa = crearAccion(
  { roles: ['jugador'], seguro: true, args: z.tuple([zSeguro]), mock: mock.solicitarPausa }, pendiente);
export const listarSuspensiones = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([z.boolean()]), mock: mock.listarSuspensiones }, pendiente);
export const listarInvestigaciones = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([z.boolean()]), mock: mock.listarInvestigaciones }, pendiente);
export const cerrarInvestigacion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, z.string().trim().min(3).max(500), zSeguro]), mock: mock.cerrarInvestigacion }, pendiente);
export const registrarAbono = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDinero, zSeguro]), mock: mock.registrarAbono }, pendiente);
export const obtenerUmbral = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([]), mock: mock.obtenerUmbral }, pendiente);
export const actualizarUmbral = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zDinero, zSeguro]), mock: mock.actualizarUmbral }, pendiente);
// Opcionales (consignaciones/retiros): si no se implementan, Andrés las deja en CA399 "No disponible".
export const registrarConsignacion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDinero, zSeguro]), mock: mock.registrarConsignacion }, pendiente);
export const registrarRetiro = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDinero, zSeguro]), mock: mock.registrarRetiro }, pendiente);
