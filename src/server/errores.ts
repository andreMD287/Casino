// Errores de negocio con código CAxxx (ver docs/errores.md).
// Sin dependencias de Next ni de 'server-only', para que también lo usen los scripts.

/** Error que aborta la acción y hace ROLLBACK. */
export class ErrorCasino extends Error {
  constructor(public readonly codigo: string, mensaje: string) {
    super(mensaje);
    this.name = 'ErrorCasino';
  }
}

/**
 * Fallo que se devuelve al cliente pero deja que la transacción haga COMMIT.
 * Se usa cuando hay que guardar algo aunque la operación falle
 * (por ejemplo, marcar un desafío de login como fallido).
 */
export class FalloConCommit {
  constructor(public readonly codigo: string, public readonly mensaje: string) {}
}

export const ERR = {
  interno: () => new ErrorCasino('CA000', 'Error interno'),
  rolNoPermitido: () => new ErrorCasino('CA002', 'No tienes permiso para esta operación'),
  credenciales: () => new FalloConCommit('CA004', 'Usuario o clave incorrectos'),
  formulario: () => new ErrorCasino('CA007', 'Formulario vencido o inválido, recarga la página'),
  sinSesion: () => new ErrorCasino('CA009', 'Tu sesión no es válida o venció; inicia sesión de nuevo'),
  datosInvalidos: (detalle: string) => new ErrorCasino('CA011', `Datos inválidos: ${detalle}`),
  pendiente: () => new ErrorCasino('CA099', 'Pendiente de implementar'),
} as const;
