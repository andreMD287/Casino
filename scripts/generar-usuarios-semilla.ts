// Genera db/90_semilla_base.sql: usuarios de prueba (A8) con salt y verificador SRP-6a,
// más juegos y opciones de apuesta.
// Usa la MISMA librería que el navegador (secure-remote-password/client), así el login real funciona.
//
//   npx tsx scripts/generar-usuarios-semilla.ts
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import * as srp from 'secure-remote-password/client';

const CLAVE = 'Casino2026*';

const USUARIOS: { usuario: string; rol: string }[] = [
  { usuario: 'admin', rol: 'administrador' },
  { usuario: 'crupier1', rol: 'crupier' },
  { usuario: 'crupier2', rol: 'crupier' },
  { usuario: 'crupier3', rol: 'crupier' },
  { usuario: 'crupier4', rol: 'crupier' },
  { usuario: 'supervisor1', rol: 'supervisor' },
  { usuario: 'supervisor2', rol: 'supervisor' },
  { usuario: 'jugador1', rol: 'jugador' },
  { usuario: 'jugador2', rol: 'jugador' },
  { usuario: 'jugador3', rol: 'jugador' },
  { usuario: 'crupier1.juega', rol: 'jugador' },
  { usuario: 'supervisor1.juega', rol: 'jugador' },
];

const lit = (s: string) => `'${s.replace(/'/g, "''")}'`;

const lineasUsuarios = USUARIOS.map(({ usuario, rol }) => {
  const salt = srp.generateSalt();
  const verificador = srp.deriveVerifier(srp.derivePrivateKey(salt, usuario, CLAVE));
  return `  PERFORM fn_crear_usuario(${lit(usuario)}, ${lit(salt)},\n    ${lit(verificador)}, ${lit(rol)});`;
});

const ruleta: [string, string][] = [];
for (let n = 0; n <= 36; n++) ruleta.push([`Pleno ${n}`, '35']);
ruleta.push(['Rojo', '1'], ['Negro', '1'], ['Par', '1'], ['Impar', '1']);
ruleta.push(['Primera docena', '2'], ['Segunda docena', '2'], ['Tercera docena', '2']);

const opciones = (juego: string, lista: [string, string][]) =>
  lista.map(([nombre, factor]) => `  ((SELECT id FROM juegos WHERE nombre = ${lit(juego)}), ${lit(nombre)}, ${factor})`);

const sql = `-- 90_semilla_base.sql (André) — GENERADO por scripts/generar-usuarios-semilla.ts. No editar a mano.
-- Usuarios de prueba (clave de todos: ${CLAVE}), juegos y opciones de apuesta.
SET ROLE casino_owner;
SET search_path = casino, public;

-- Usuarios (salt y verificador SRP-6a con SHA-256; la clave no se guarda).
DO $$
BEGIN
${lineasUsuarios.join('\n')}
END
$$;

-- Juegos
INSERT INTO juegos (nombre, registro_detallado) VALUES
  ('Ruleta', true),
  ('Blackjack', true),
  ('Póker', false);

-- Opciones de apuesta (factor de pago: premio = monto × factor)
INSERT INTO opciones_apuesta (juego_id, nombre, factor_pago) VALUES
${[...opciones('Ruleta', ruleta), ...opciones('Blackjack', [['Mano ganadora', '1'], ['Blackjack', '1.5']]), ...opciones('Póker', [['Mano ganadora', '1']])].join(',\n')};
`;

const destino = join(__dirname, '..', 'db', '90_semilla_base.sql');
writeFileSync(destino, sql, 'utf8');
console.log(`Escrito ${destino} (${USUARIOS.length} usuarios)`);
