// ===== src/lib/contrato.ts — tipos compartidos (contrato A7). No cambiar nombres sin acuerdo de los tres. =====
export type Rol = 'administrador' | 'crupier' | 'supervisor' | 'jugador';
export type Dinero = string;          // numeric de PostgreSQL como string; nunca float
export type FechaISO = string;
export type Resultado<T> = { ok: true; datos: T } | { ok: false; error: { codigo: string; mensaje: string } };
export type CamposSeguros = { fechahora: string; firma: string };   // firma = SHA-256(canal + fechahora)
export type Sesion = { usuarioId: number; usuario: string; nombre: string; rol: Rol };
export type Credenciales = { usuario: string; salt: string; verificador: string };

export type Juego = { id: number; nombre: string; registroDetallado: boolean };
export type Cargo = 'administrador' | 'crupier' | 'supervisor';
export type Empleado = { id: number; usuario: string; nombre: string; documento: string; cargo: Cargo;
  salarioMensual: Dinero; activo: boolean; competencias: { juegoId: number; juego: string }[] };
export type Mesa = { id: number; codigo: string; juegoId: number; juego: string; registroDetallado: boolean;
  montoMinimo: Dinero; montoMaximo: Dinero; activa: boolean };
export type Jornada = { id: number; fecha: string };
export type Turno = { id: number; jornadaId: number; numero: number; inicio: FechaISO; fin: FechaISO };
export type Concepto = 'Genera ganancias' | 'Genera pérdidas' | 'Sospecha de fraude' | 'Comportamiento neutro';
export type Asignacion = { id: number; turnoId: number; turnoNumero: number; inicio: FechaISO; fin: FechaISO;
  mesaId: number; mesaCodigo: string; juego: string; crupierId: number; crupierNombre: string;
  supervisorId: number; supervisorNombre: string; concepto: Concepto | null; observacion: string | null };

export type EstadoJugador = 'Activo' | 'Suspendido' | 'Investigación' | 'Inactivo';
export type Jugador = { id: number; codigo: string; nombre: string; documento: string; fechaNacimiento: string;
  saldo: Dinero; estado: EstadoJugador; suspendidoHasta: FechaISO | null; esEmpleado: boolean; activo: boolean };
export type Movimiento = { id: number; tipo: 'consignacion' | 'retiro' | 'apuesta' | 'devolucion' | 'premio';
  monto: Dinero; saldoResultante: Dinero; fecha: FechaISO; apuestaId: number | null };
export type Suspension = { id: number; jugadorId: number; jugadorCodigo: string; jugadorNombre: string;
  motivo: 'perdida_diaria' | 'pausa_voluntaria' | 'deuda_empleado'; inicio: FechaISO; fin: FechaISO | null;
  levantadaEn: FechaISO | null; activa: boolean };
export type Investigacion = { id: number; jugadorId: number; jugadorCodigo: string; jugadorNombre: string;
  abiertaEn: FechaISO; cerradaEn: FechaISO | null; resolucion: string | null };

export type OpcionApuesta = { id: number; juegoId: number; nombre: string; factorPago: string; activa: boolean };
export type EstadoRonda = 'abierta' | 'cerrada' | 'anulada';
export type Ronda = { id: number; mesaId: number; numero: number; inicio: FechaISO; cierre: FechaISO | null;
  estado: EstadoRonda; resultado: { opcionId: number; nombre: string }[] };
export type EstadoApuesta = 'pendiente' | 'ganada' | 'perdida' | 'anulada';
export type Apuesta = { id: number; rondaId: number; mesaCodigo: string; rondaNumero: number; jugadorId: number;
  jugadorCodigo: string; jugadorNombre: string; opcionId: number; opcion: string; monto: Dinero;
  factorPago: string; estado: EstadoApuesta; premio: Dinero | null; creadaEn: FechaISO; liquidadaEn: FechaISO | null };
export type Historial = { jugador: Jugador; apuestas: Apuesta[]; movimientos: Movimiento[];
  suspensiones: Suspension[]; investigaciones: Investigacion[]; deudaEmpleado: Dinero | null };
export type MesaCrupier = { asignacionId: number; mesa: Mesa; inicioTurno: FechaISO; finTurno: FechaISO;
  rondaAbierta: Ronda | null };
export type ResumenLiquidacion = { ganadas: number; perdidas: number; totalApostado: Dinero;
  totalPremios: Dinero; resultadoCasino: Dinero };
export type JugadorParaApuesta = { jugadorId: number; codigo: string; nombre: string; saldo: Dinero;
  puedeApostar: boolean; motivo: string | null };
export type FilaReporte = { fecha: string; turnoNumero: number; mesaCodigo: string; crupier: string;
  supervisor: string; totalApostado: Dinero; totalPremios: Dinero; resultadoNominal: Dinero; concepto: Concepto | null };
