'use server';
// Acciones de mesas, jornadas, turnos, asignaciones y conceptos. Creado por André en la fase 0 con mocks;
// desde ahí es de Andrés. En modo real devuelven CA099 "Pendiente de implementar" hasta que Andrés las reemplace.
import { z } from 'zod';
import { crearAccion, ERR, zDinero, zId, zSeguro } from '@/server/accion';
import * as mock from '@/server/mocks/mesas';

const pendiente = async (): Promise<never> => {
  throw ERR.pendiente();
};
const zDatosMesa = z.object({ codigo: z.string().trim().min(1).max(20), juegoId: zId, montoMinimo: zDinero, montoMaximo: zDinero });
const zConcepto = z.enum(['Genera ganancias', 'Genera pérdidas', 'Sospecha de fraude', 'Comportamiento neutro']);
const zFecha = z.iso.datetime({ offset: true });

export const listarMesas = crearAccion(
  { roles: ['administrador', 'crupier', 'supervisor'], seguro: false, args: z.tuple([]), mock: mock.listarMesas }, pendiente);
export const crearMesa = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zDatosMesa, zSeguro]), mock: mock.crearMesa }, pendiente);
export const actualizarMesa = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDatosMesa, zSeguro]), mock: mock.actualizarMesa }, pendiente);
export const desactivarMesa = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.desactivarMesa }, pendiente);
export const listarJornadas = crearAccion(
  { roles: ['administrador', 'supervisor'], seguro: false, args: z.tuple([]), mock: mock.listarJornadas }, pendiente);
export const crearJornada = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([z.iso.date(), zSeguro]), mock: mock.crearJornada }, pendiente);
export const listarTurnos = crearAccion(
  { roles: ['administrador', 'supervisor'], seguro: false, args: z.tuple([zId]), mock: mock.listarTurnos }, pendiente);
export const crearTurno = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, z.object({ inicio: zFecha, fin: zFecha }), zSeguro]), mock: mock.crearTurno }, pendiente);
export const eliminarTurno = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.eliminarTurno }, pendiente);
export const listarAsignaciones = crearAccion(
  { roles: ['administrador', 'supervisor'], seguro: false, args: z.tuple([zId]), mock: mock.listarAsignaciones }, pendiente);
export const crearAsignacion = crearAccion(
  {
    roles: ['administrador'],
    seguro: true,
    args: z.tuple([z.object({ turnoId: zId, mesaId: zId, crupierId: zId, supervisorId: zId }), zSeguro]),
    mock: mock.crearAsignacion,
  },
  pendiente,
);
export const eliminarAsignacion = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.eliminarAsignacion }, pendiente);
export const misTurnosSupervisor = crearAccion(
  { roles: ['supervisor'], seguro: false, args: z.tuple([]), mock: mock.misTurnosSupervisor }, pendiente);
export const emitirConcepto = crearAccion(
  {
    roles: ['supervisor'],
    seguro: true,
    args: z.tuple([zId, zConcepto, z.string().trim().max(500).nullable(), zSeguro]),
    mock: mock.emitirConcepto,
  },
  pendiente,
);
