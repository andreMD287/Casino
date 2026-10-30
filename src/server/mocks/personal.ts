// Mock de personal (MODO_MOCK=1). Creado por André en la fase 0; desde ahí es de Andrés.
import type { Cargo, CamposSeguros, Credenciales, Dinero, Empleado, Juego } from '@/lib/contrato';
import type { CtxMock } from '@/server/accion';
import { ErrorCasino } from '@/server/errores';
import { mockEmpleados, mockJuegos, mockUsuarios, siguienteId } from '@/server/mocks/datos';

type DatosEmpleado = { nombre: string; documento: string; cargo: Cargo; salarioMensual: Dinero };

const buscar = (id: number) => {
  const e = mockEmpleados.find((x) => x.id === id);
  if (!e) throw new ErrorCasino('CA101', 'El empleado no existe');
  return e;
};
const copia = (e: Empleado): Empleado => ({ ...e, competencias: [...e.competencias] });

export async function listarJuegos(_ctx: CtxMock): Promise<Juego[]> {
  return mockJuegos.map((j) => ({ ...j }));
}

export async function listarEmpleados(_ctx: CtxMock): Promise<Empleado[]> {
  return mockEmpleados.map(copia);
}

export async function crearEmpleado(_ctx: CtxMock, datos: DatosEmpleado, cred: Credenciales, _s: CamposSeguros): Promise<Empleado> {
  if (mockUsuarios.some((u) => u.usuario === cred.usuario)) throw new ErrorCasino('CA003', `El usuario "${cred.usuario}" ya existe`);
  if (mockEmpleados.some((e) => e.documento === datos.documento)) throw new ErrorCasino('CA102', 'Ya existe un empleado con ese documento');
  mockUsuarios.push({ id: siguienteId(mockUsuarios), usuario: cred.usuario, rol: datos.cargo });
  const e: Empleado = { id: siguienteId(mockEmpleados), usuario: cred.usuario, ...datos, activo: true, competencias: [] };
  mockEmpleados.push(e);
  return copia(e);
}

export async function actualizarEmpleado(_ctx: CtxMock, id: number, datos: DatosEmpleado, _s: CamposSeguros): Promise<Empleado> {
  const e = buscar(id);
  Object.assign(e, datos);
  return copia(e);
}

export async function desactivarEmpleado(_ctx: CtxMock, id: number, _s: CamposSeguros): Promise<null> {
  buscar(id).activo = false;
  return null;
}

export async function asignarCompetencia(_ctx: CtxMock, empleadoId: number, juegoId: number, _s: CamposSeguros): Promise<null> {
  const e = buscar(empleadoId);
  const j = mockJuegos.find((x) => x.id === juegoId);
  if (!j) throw new ErrorCasino('CA103', 'El juego no existe');
  if (!e.competencias.some((c) => c.juegoId === juegoId)) e.competencias.push({ juegoId, juego: j.nombre });
  return null;
}

export async function quitarCompetencia(_ctx: CtxMock, empleadoId: number, juegoId: number, _s: CamposSeguros): Promise<null> {
  const e = buscar(empleadoId);
  e.competencias = e.competencias.filter((c) => c.juegoId !== juegoId);
  return null;
}
