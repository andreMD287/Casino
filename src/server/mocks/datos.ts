// Datos de ejemplo EN MEMORIA para MODO_MOCK=1 (compartidos por todos los mocks).
// Imitan las semillas: mismos usuarios, juegos y opciones; 3 mesas, la jornada de hoy con
// un turno terminado, el actual y el siguiente; rondas y apuestas en todos los estados;
// jugadores en los 4 estados. Los mocks modifican estos arreglos para simular escrituras.
import type {
  Apuesta, Asignacion, Empleado, Investigacion, Jornada, Juego, Jugador, Mesa, Movimiento,
  OpcionApuesta, Rol, Ronda, Suspension, Turno,
} from '@/lib/contrato';

const MIN = 60_000;
const ahora = Date.now();
const iso = (ms: number) => new Date(ms).toISOString();
const hoy = new Date(ahora - 5 * 60 * MIN).toISOString().slice(0, 10); // fecha aproximada en Bogotá

export const mockUsuarios: { id: number; usuario: string; rol: Rol }[] = [
  { id: 1, usuario: 'admin', rol: 'administrador' },
  { id: 2, usuario: 'crupier1', rol: 'crupier' },
  { id: 3, usuario: 'crupier2', rol: 'crupier' },
  { id: 4, usuario: 'crupier3', rol: 'crupier' },
  { id: 5, usuario: 'crupier4', rol: 'crupier' },
  { id: 6, usuario: 'supervisor1', rol: 'supervisor' },
  { id: 7, usuario: 'supervisor2', rol: 'supervisor' },
  { id: 8, usuario: 'jugador1', rol: 'jugador' },
  { id: 9, usuario: 'jugador2', rol: 'jugador' },
  { id: 10, usuario: 'jugador3', rol: 'jugador' },
  { id: 11, usuario: 'crupier1.juega', rol: 'jugador' },
  { id: 12, usuario: 'supervisor1.juega', rol: 'jugador' },
];

export const mockJuegos: Juego[] = [
  { id: 1, nombre: 'Ruleta', registroDetallado: true },
  { id: 2, nombre: 'Blackjack', registroDetallado: true },
  { id: 3, nombre: 'Póker', registroDetallado: false },
];

export const mockOpciones: OpcionApuesta[] = (() => {
  const lista: OpcionApuesta[] = [];
  let id = 1;
  const agregar = (juegoId: number, nombre: string, factorPago: string) => lista.push({ id: id++, juegoId, nombre, factorPago, activa: true });
  for (let n = 0; n <= 36; n++) agregar(1, `Pleno ${n}`, '35.00');
  for (const n of ['Rojo', 'Negro', 'Par', 'Impar']) agregar(1, n, '1.00');
  for (const n of ['Primera docena', 'Segunda docena', 'Tercera docena']) agregar(1, n, '2.00');
  agregar(2, 'Mano ganadora', '1.00');
  agregar(2, 'Blackjack', '1.50');
  agregar(3, 'Mano ganadora', '1.00');
  return lista;
})();
export const opcionPorNombre = (juegoId: number, nombre: string) => mockOpciones.find((o) => o.juegoId === juegoId && o.nombre === nombre)!;

const juego = (id: number) => mockJuegos.find((j) => j.id === id)!;

export const mockEmpleados: Empleado[] = [
  { id: 1, usuario: 'admin', nombre: 'Ana Administradora', documento: '1001', cargo: 'administrador', salarioMensual: '6000000.00', activo: true, competencias: [] },
  { id: 2, usuario: 'crupier1', nombre: 'Carlos Crupier', documento: '1002', cargo: 'crupier', salarioMensual: '2500000.00', activo: true, competencias: [1, 2, 3].map((j) => ({ juegoId: j, juego: juego(j).nombre })) },
  { id: 3, usuario: 'crupier2', nombre: 'Camila Crupier', documento: '1003', cargo: 'crupier', salarioMensual: '2500000.00', activo: true, competencias: [1, 2, 3].map((j) => ({ juegoId: j, juego: juego(j).nombre })) },
  { id: 4, usuario: 'crupier3', nombre: 'Cristian Crupier', documento: '1004', cargo: 'crupier', salarioMensual: '2400000.00', activo: true, competencias: [1, 2].map((j) => ({ juegoId: j, juego: juego(j).nombre })) },
  { id: 5, usuario: 'crupier4', nombre: 'Clara Crupier', documento: '1005', cargo: 'crupier', salarioMensual: '2400000.00', activo: true, competencias: [3].map((j) => ({ juegoId: j, juego: juego(j).nombre })) },
  { id: 6, usuario: 'supervisor1', nombre: 'Sergio Supervisor', documento: '1006', cargo: 'supervisor', salarioMensual: '4000000.00', activo: true, competencias: [1, 2, 3].map((j) => ({ juegoId: j, juego: juego(j).nombre })) },
  { id: 7, usuario: 'supervisor2', nombre: 'Sofía Supervisora', documento: '1007', cargo: 'supervisor', salarioMensual: '4000000.00', activo: true, competencias: [1, 2, 3].map((j) => ({ juegoId: j, juego: juego(j).nombre })) },
];

export const mockMesas: Mesa[] = [
  { id: 1, codigo: 'R-01', juegoId: 1, juego: 'Ruleta', registroDetallado: true, montoMinimo: '10.00', montoMaximo: '1000.00', activa: true },
  { id: 2, codigo: 'B-01', juegoId: 2, juego: 'Blackjack', registroDetallado: true, montoMinimo: '20.00', montoMaximo: '2000.00', activa: true },
  { id: 3, codigo: 'P-01', juegoId: 3, juego: 'Póker', registroDetallado: false, montoMinimo: '50.00', montoMaximo: '5000.00', activa: true },
];

export const mockJornadas: Jornada[] = [{ id: 1, fecha: hoy }];

// Turno 1 terminado, turno 2 vigente, turno 3 siguiente (90 minutos cada uno).
export const mockTurnos: Turno[] = [
  { id: 1, jornadaId: 1, numero: 1, inicio: iso(ahora - 150 * MIN), fin: iso(ahora - 60 * MIN) },
  { id: 2, jornadaId: 1, numero: 2, inicio: iso(ahora - 30 * MIN), fin: iso(ahora + 60 * MIN) },
  { id: 3, jornadaId: 1, numero: 3, inicio: iso(ahora + 60 * MIN), fin: iso(ahora + 150 * MIN) },
];

const emp = (id: number) => mockEmpleados.find((e) => e.id === id)!;
const asig = (id: number, turnoId: number, mesaId: number, crupierId: number, supervisorId: number,
  concepto: Asignacion['concepto'] = null, observacion: string | null = null): Asignacion => {
  const t = mockTurnos.find((x) => x.id === turnoId)!;
  const m = mockMesas.find((x) => x.id === mesaId)!;
  return { id, turnoId, turnoNumero: t.numero, inicio: t.inicio, fin: t.fin, mesaId, mesaCodigo: m.codigo, juego: m.juego,
    crupierId, crupierNombre: emp(crupierId).nombre, supervisorId, supervisorNombre: emp(supervisorId).nombre, concepto, observacion };
};
// Rotación: ningún crupier repite mesa en la jornada.
export const mockAsignaciones: Asignacion[] = [
  asig(1, 1, 1, 3, 6, 'Genera ganancias', 'Ritmo de juego alto y ordenado'),
  asig(2, 1, 2, 4, 6, 'Comportamiento neutro', null),
  asig(3, 1, 3, 2, 7, 'Sospecha de fraude', 'Revisar repartos de la ronda 1'),
  asig(4, 2, 1, 2, 6),
  asig(5, 2, 2, 3, 6),
  asig(6, 2, 3, 5, 7),
  asig(7, 3, 2, 2, 6),
  asig(8, 3, 3, 3, 7),
  asig(9, 3, 1, 4, 6),
];

export const mockJugadores: Jugador[] = [
  { id: 1, codigo: 'J-000001', nombre: 'Juliana Jugadora', documento: '2001', fechaNacimiento: '1990-04-12', saldo: '5230.00', estado: 'Activo', suspendidoHasta: null, esEmpleado: false, activo: true },
  { id: 2, codigo: 'J-000002', nombre: 'Julián Jugador', documento: '2002', fechaNacimiento: '1985-09-30', saldo: '1200.00', estado: 'Suspendido', suspendidoHasta: iso(ahora + 20 * 60 * MIN), esEmpleado: false, activo: true },
  { id: 3, codigo: 'J-000003', nombre: 'Jimena Jugadora', documento: '2003', fechaNacimiento: '2000-01-20', saldo: '0.00', estado: 'Inactivo', suspendidoHasta: null, esEmpleado: false, activo: false },
  { id: 4, codigo: 'J-000004', nombre: 'Carlos Crupier', documento: '1002', fechaNacimiento: '1992-07-07', saldo: '9800.00', estado: 'Investigación', suspendidoHasta: null, esEmpleado: true, activo: true },
  { id: 5, codigo: 'J-000005', nombre: 'Sergio Supervisor', documento: '1006', fechaNacimiento: '1980-03-03', saldo: '300.00', estado: 'Activo', suspendidoHasta: null, esEmpleado: true, activo: true },
];
export const mockJugadorDeUsuario: Record<number, number> = { 8: 1, 9: 2, 10: 3, 11: 4, 12: 5 };

const ronda = (id: number, mesaId: number, numero: number, inicioMin: number, cierreMin: number | null,
  estado: Ronda['estado'], resultado: string[] = []): Ronda => ({
  id, mesaId, numero, inicio: iso(ahora + inicioMin * MIN), cierre: cierreMin === null ? null : iso(ahora + cierreMin * MIN), estado,
  resultado: resultado.map((n) => { const o = opcionPorNombre(mockMesas.find((m) => m.id === mesaId)!.juegoId, n); return { opcionId: o.id, nombre: o.nombre }; }),
});
export const mockRondas: (Ronda & { asignacionId: number })[] = [
  { ...ronda(1, 1, 1, -140, -130, 'cerrada', ['Pleno 17', 'Negro', 'Impar']), asignacionId: 1 },
  { ...ronda(2, 1, 2, -125, -118, 'cerrada', ['Pleno 4', 'Negro', 'Par']), asignacionId: 1 },
  { ...ronda(3, 2, 1, -140, -132, 'cerrada', ['Mano ganadora']), asignacionId: 2 },
  { ...ronda(4, 3, 1, -145, -100, 'cerrada'), asignacionId: 3 },
  { ...ronda(5, 1, 3, -25, -20, 'anulada'), asignacionId: 4 },
  { ...ronda(6, 1, 4, -10, null, 'abierta'), asignacionId: 4 },
];

const jug = (id: number) => mockJugadores.find((j) => j.id === id)!;
let siguienteApuesta = 1;
const apuesta = (rondaId: number, jugadorId: number, opcion: string, monto: string, estado: Apuesta['estado']): Apuesta => {
  const r = mockRondas.find((x) => x.id === rondaId)!;
  const m = mockMesas.find((x) => x.id === r.mesaId)!;
  const o = opcionPorNombre(m.juegoId, opcion);
  const premio = estado === 'ganada' ? (Number(monto) * Number(o.factorPago)).toFixed(2) : null;
  return { id: siguienteApuesta++, rondaId, mesaCodigo: m.codigo, rondaNumero: r.numero, jugadorId, jugadorCodigo: jug(jugadorId).codigo,
    jugadorNombre: jug(jugadorId).nombre, opcionId: o.id, opcion: o.nombre, monto, factorPago: o.factorPago, estado, premio,
    creadaEn: r.inicio, liquidadaEn: estado === 'ganada' || estado === 'perdida' ? (r.cierre ?? r.inicio) : null };
};
export const mockApuestas: Apuesta[] = [
  apuesta(1, 1, 'Pleno 17', '20.00', 'ganada'),
  apuesta(1, 1, 'Rojo', '100.00', 'perdida'),
  apuesta(1, 5, 'Impar', '50.00', 'ganada'),
  apuesta(2, 1, 'Negro', '200.00', 'ganada'),
  apuesta(2, 2, 'Primera docena', '150.00', 'perdida'),
  apuesta(3, 4, 'Mano ganadora', '500.00', 'ganada'),
  apuesta(3, 1, 'Blackjack', '100.00', 'perdida'),
  apuesta(4, 4, 'Mano ganadora', '1000.00', 'ganada'),
  apuesta(4, 5, 'Mano ganadora', '200.00', 'perdida'),
  apuesta(5, 1, 'Rojo', '50.00', 'anulada'),
  apuesta(6, 1, 'Pleno 7', '20.00', 'pendiente'),
  apuesta(6, 1, 'Rojo', '100.00', 'pendiente'),
  apuesta(6, 5, 'Par', '30.00', 'pendiente'),
];
export const nuevaApuestaId = () => siguienteApuesta++;

export const mockMovimientos: (Movimiento & { jugadorId: number })[] = [
  { id: 1, jugadorId: 1, tipo: 'consignacion', monto: '5000.00', saldoResultante: '5000.00', fecha: iso(ahora - 200 * MIN), apuestaId: null },
  { id: 2, jugadorId: 1, tipo: 'apuesta', monto: '20.00', saldoResultante: '4980.00', fecha: iso(ahora - 139 * MIN), apuestaId: 1 },
  { id: 3, jugadorId: 1, tipo: 'apuesta', monto: '100.00', saldoResultante: '4880.00', fecha: iso(ahora - 139 * MIN), apuestaId: 2 },
  { id: 4, jugadorId: 1, tipo: 'devolucion', monto: '20.00', saldoResultante: '4900.00', fecha: iso(ahora - 130 * MIN), apuestaId: 1 },
  { id: 5, jugadorId: 1, tipo: 'premio', monto: '700.00', saldoResultante: '5600.00', fecha: iso(ahora - 130 * MIN), apuestaId: 1 },
  { id: 6, jugadorId: 2, tipo: 'consignacion', monto: '1350.00', saldoResultante: '1350.00', fecha: iso(ahora - 200 * MIN), apuestaId: null },
  { id: 7, jugadorId: 2, tipo: 'apuesta', monto: '150.00', saldoResultante: '1200.00', fecha: iso(ahora - 124 * MIN), apuestaId: 5 },
];

export const mockSuspensiones: Suspension[] = [
  { id: 1, jugadorId: 2, jugadorCodigo: 'J-000002', jugadorNombre: 'Julián Jugador', motivo: 'pausa_voluntaria', inicio: iso(ahora - 4 * 60 * MIN), fin: iso(ahora + 20 * 60 * MIN), levantadaEn: null, activa: true },
  { id: 2, jugadorId: 1, jugadorCodigo: 'J-000001', jugadorNombre: 'Juliana Jugadora', motivo: 'perdida_diaria', inicio: iso(ahora - 72 * 60 * MIN), fin: iso(ahora - 48 * 60 * MIN), levantadaEn: null, activa: false },
  { id: 3, jugadorId: 5, jugadorCodigo: 'J-000005', jugadorNombre: 'Sergio Supervisor', motivo: 'deuda_empleado', inicio: iso(ahora - 30 * 24 * 60 * MIN), fin: null, levantadaEn: iso(ahora - 10 * 24 * 60 * MIN), activa: false },
];

export const mockInvestigaciones: Investigacion[] = [
  { id: 1, jugadorId: 4, jugadorCodigo: 'J-000004', jugadorNombre: 'Carlos Crupier', abiertaEn: iso(ahora - 100 * MIN), cerradaEn: null, resolucion: null },
];

export const mockConfiguracion = { umbralPerdidaDiaria: '3000.00' };
export const mockAbonos: { empleadoId: number; monto: string }[] = [];

/** Siguiente id libre de un arreglo con campo id. */
export const siguienteId = (lista: { id: number }[]) => lista.reduce((m, x) => Math.max(m, x.id), 0) + 1;

// ---- Dinero en el mock: se calcula en centavos enteros (nunca float acumulado) ----
export const centavos = (d: string) => Math.round(Number(d) * 100);
export const dinero = (c: number) => (c / 100).toFixed(2);

/** Equivalente en memoria de fn_mover_saldo. */
export function moverSaldoMock(jugadorId: number, tipo: Movimiento['tipo'], monto: string, apuestaId: number | null = null): string {
  const j = mockJugadores.find((x) => x.id === jugadorId);
  if (!j) throw Object.assign(new Error('El jugador no existe'), { code: 'CA012' });
  const signo = tipo === 'retiro' || tipo === 'apuesta' ? -1 : 1;
  const nuevo = centavos(j.saldo) + signo * centavos(monto);
  if (nuevo < 0) throw Object.assign(new Error(`Saldo insuficiente: el jugador tiene ${j.saldo} y se necesitan ${monto}`), { code: 'CA010' });
  j.saldo = dinero(nuevo);
  mockMovimientos.push({ id: siguienteId(mockMovimientos), jugadorId, tipo, monto, saldoResultante: j.saldo, fecha: new Date().toISOString(), apuestaId });
  return j.saldo;
}
