import 'server-only';
import { unstable_rethrow } from 'next/navigation';
import { z } from 'zod';
import type { CamposSeguros, Resultado, Rol, Sesion } from '@/lib/contrato';
import { withTx, type Consulta } from '@/server/db';
import { modoMock, obtenerCanal, obtenerSesionInterna, type SesionInterna } from '@/server/auth/sesion';
import { rolPermitido, verificarCamposSeguros } from '@/server/auth/nucleo';
import { ERR, ErrorCasino, FalloConCommit } from '@/server/errores';

export { ErrorCasino, FalloConCommit, ERR } from '@/server/errores';

/** Contexto que recibe la implementación real de una acción. */
export type Ctx = { sesion: SesionInterna | null; q: Consulta };
/** Contexto que recibe un mock. */
export type CtxMock = { sesion: Sesion | null };

// ---- Esquemas zod reutilizables (solo formato; las reglas de negocio están en la BD) ----
export const zId = z.number().int().positive();
export const zDinero = z.string().regex(/^\d{1,12}(\.\d{1,2})?$/, 'monto con máximo 2 decimales');
export const zFactor = z.string().regex(/^\d{1,6}(\.\d{1,2})?$/, 'factor con máximo 2 decimales');
export const zSeguro = z.object({ fechahora: z.string().min(1).max(40), firma: z.string().regex(/^[0-9a-f]{64}$/) });
export const zCredenciales = z.object({
  usuario: z.string().regex(/^[a-z0-9_.]{3,30}$/, 'usuario de 3 a 30 caracteres: a-z, 0-9, _ o .'),
  salt: z.string().regex(/^[0-9a-f]{16,128}$/),
  verificador: z.string().regex(/^[0-9a-f]{64,1024}$/),
});

type Opciones<A extends unknown[], I extends unknown[], T> = {
  /** Roles permitidos, o 'publica' si no requiere sesión. */
  roles: Rol[] | 'publica';
  /** Si es true, el último argumento es CamposSeguros y se verifica su firma. */
  seguro: boolean;
  /** Esquema zod (z.tuple) de los argumentos, para validar su formato. */
  args: z.ZodType<A, I>;
  /** Implementación usada cuando MODO_MOCK=1. */
  mock?: (ctx: CtxMock, ...args: A) => T | Promise<T>;
};

function fallo(codigo: string, mensaje: string): Resultado<never> {
  return { ok: false, error: { codigo, mensaje } };
}

/**
 * Envuelve una Server Action: sesión y rol → formato de argumentos → formulario seguro →
 * transacción con el actor fijado → traducción de errores (CAxxx al usuario; lo demás, CA000).
 */
export function crearAccion<A extends unknown[], I extends unknown[], T>(
  opciones: Opciones<A, I, T>,
  fn: (ctx: Ctx, ...args: A) => Promise<T | FalloConCommit>,
): (...args: I) => Promise<Resultado<T>> {
  return async (...argsCrudos) => {
    try {
      // 1. Sesión y rol (capa 2 de autorización; la capa 3 es fn_exigir_rol en SQL).
      const sesion = await obtenerSesionInterna();
      if (opciones.roles !== 'publica') {
        if (!sesion) throw ERR.sinSesion();
        if (!rolPermitido(sesion.rol, opciones.roles)) throw ERR.rolNoPermitido();
      }

      // 2. Formato de los argumentos.
      const parseo = opciones.args.safeParse(argsCrudos);
      if (!parseo.success) {
        const detalle = parseo.error.issues.map((i) => `${i.path.join('.') || 'argumentos'}: ${i.message}`).join('; ');
        throw ERR.datosInvalidos(detalle);
      }
      const args = parseo.data;

      // 3. Formulario seguro.
      if (opciones.seguro) {
        const campos = args[args.length - 1] as CamposSeguros;
        if (!verificarCamposSeguros(await obtenerCanal(), campos)) throw ERR.formulario();
      }

      // 4. Mock o BD.
      if (modoMock()) {
        if (!opciones.mock) throw ERR.pendiente();
        const sesionPublica = sesion ? { usuarioId: sesion.usuarioId, usuario: sesion.usuario, nombre: sesion.nombre, rol: sesion.rol } : null;
        return { ok: true, datos: await opciones.mock({ sesion: sesionPublica }, ...args) };
      }

      const resultado = await withTx(sesion?.usuarioId ?? null, (q) => fn({ sesion, q }, ...args));
      if (resultado instanceof FalloConCommit) return fallo(resultado.codigo, resultado.mensaje);
      return { ok: true, datos: resultado };
    } catch (err) {
      unstable_rethrow(err); // redirect(), notFound(), etc. de Next se dejan pasar
      if (err instanceof ErrorCasino) return fallo(err.codigo, err.message);
      const pg = err as { code?: unknown; message?: unknown };
      if (typeof pg?.code === 'string' && /^CA\d{3}$/.test(pg.code)) return fallo(pg.code, String(pg.message));
      console.error('[crearAccion] error no controlado', err);
      return fallo('CA000', 'Error interno');
    }
  };
}

/** Convierte un objeto de filas snake_case de la BD a camelCase. */
export function camel<T>(fila: Record<string, unknown>): T {
  const salida: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fila)) salida[k.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase())] = v;
  return salida as T;
}
