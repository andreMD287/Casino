// SRP-6a del lado del navegador (André). La clave NUNCA sale de este archivo:
// al servidor solo viajan el usuario, A, M1 y, en el registro, salt y verificador.
import * as srp from 'secure-remote-password/client';
import type { Credenciales, Resultado, Rol } from '@/lib/contrato';
import { loginPaso1, loginPaso2 } from '@/server/acciones/auth';

const normalizar = (usuario: string) => usuario.trim().toLowerCase();

/**
 * Para registrar un usuario o cambiar su clave: genera el salt y deriva
 * x = SHA-256(salt | SHA-256(usuario ":" clave)) y el verificador v = g^x mod N.
 */
export async function derivarCredenciales(usuario: string, clave: string): Promise<Credenciales> {
  const u = normalizar(usuario);
  const salt = srp.generateSalt();
  const privada = srp.derivePrivateKey(salt, u, clave);
  return { usuario: u, salt, verificador: srp.deriveVerifier(privada) };
}

/**
 * Login en dos pasos. Si sale bien, el servidor ya dejó la cookie de sesión.
 * Además se verifica M2: si el servidor no conoce el verificador, no puede calcularlo (CA008).
 */
export async function iniciarSesion(usuario: string, clave: string): Promise<Resultado<{ rol: Rol }>> {
  const u = normalizar(usuario);
  const efimero = srp.generateEphemeral();

  const paso1 = await loginPaso1(u, efimero.public);
  if (!paso1.ok) return paso1;
  const { idDesafio, salt, B } = paso1.datos;

  let sesion: srp.Session;
  try {
    const privada = srp.derivePrivateKey(salt, u, clave);
    sesion = srp.deriveSession(efimero.secret, B, salt, u, privada);
  } catch {
    return { ok: false, error: { codigo: 'CA004', mensaje: 'Usuario o clave incorrectos' } };
  }

  const paso2 = await loginPaso2(idDesafio, sesion.proof);
  if (!paso2.ok) return paso2;

  try {
    srp.verifySession(efimero.public, sesion, paso2.datos.M2);
  } catch {
    return { ok: false, error: { codigo: 'CA008', mensaje: 'No se pudo verificar el servidor' } };
  }
  return { ok: true, datos: { rol: paso2.datos.rol } };
}
