'use server';
// Acciones de personal. Creado por André en la fase 0 con mocks; desde ahí es de Andrés.
// En modo real devuelven CA099 "Pendiente de implementar" hasta que Andrés las reemplace.
import { z } from 'zod';
import { crearAccion, ERR, zCredenciales, zDinero, zId, zSeguro } from '@/server/accion';
import * as mock from '@/server/mocks/personal';

const pendiente = async (): Promise<never> => {
  throw ERR.pendiente();
};
const TODOS = ['administrador', 'crupier', 'supervisor', 'jugador'] as const;
const zCargo = z.enum(['administrador', 'crupier', 'supervisor']);
const zDatosEmpleado = z.object({
  nombre: z.string().trim().min(3).max(100),
  documento: z.string().trim().min(3).max(20),
  cargo: zCargo,
  salarioMensual: zDinero,
});

export const listarJuegos = crearAccion(
  { roles: [...TODOS], seguro: false, args: z.tuple([]), mock: mock.listarJuegos }, pendiente);
export const listarEmpleados = crearAccion(
  { roles: ['administrador'], seguro: false, args: z.tuple([]), mock: mock.listarEmpleados }, pendiente);
export const crearEmpleado = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zDatosEmpleado, zCredenciales, zSeguro]), mock: mock.crearEmpleado }, pendiente);
export const actualizarEmpleado = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zDatosEmpleado, zSeguro]), mock: mock.actualizarEmpleado }, pendiente);
export const desactivarEmpleado = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zSeguro]), mock: mock.desactivarEmpleado }, pendiente);
export const asignarCompetencia = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zId, zSeguro]), mock: mock.asignarCompetencia }, pendiente);
export const quitarCompetencia = crearAccion(
  { roles: ['administrador'], seguro: true, args: z.tuple([zId, zId, zSeguro]), mock: mock.quitarCompetencia }, pendiente);
