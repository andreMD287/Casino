// Prueba de punta a punta contra la app real (MODO_MOCK=0) — André.
// Uso: ./db/run_all.sh  →  npm run build && npm start -- -p 3100  →  node scripts/probar-admin.mjs
// (lee PGHOST/PGPORT/PGUSER/PGPASSWORD de .env.local para consultar datos de la semilla)
import { createRequire } from 'node:module';
import { config } from 'dotenv';
config({ path: '.env.local' });
const RAIZ = process.argv[2] ?? process.cwd();
const require = createRequire(RAIZ + '/package.json');
const srp = require('secure-remote-password/client');
const { Pool } = require('pg');
const manifest = require(RAIZ + '/.next/server/server-reference-manifest.json');
const BASE = 'http://localhost:3100';
const db = new Pool({ database: 'casino', max: 1 });
let ok = 0, fallo = 0;
const v = (d, c, det = '') => { if (c) { ok++; console.log(`[OK] ${d}`); } else { fallo++; console.log(`[FALLO] ${d} ${det}`); } };
const j = (x) => JSON.stringify(x).slice(0, 200);
const err = (r, cod) => r && r.ok === false && r.error.codigo === cod;

function acc(nombre) {
  const e = Object.entries(manifest.node).filter(([, x]) => x.exportedName === nombre);
  if (!e.length) throw new Error('acción no encontrada: ' + nombre);
  const [id, x] = e[0];
  const aRuta = (w) => { const r = '/' + w.replace(/^app\//, '').replace(/\/page$/, '').split('/').filter((s) => !/^\(.*\)$/.test(s)).map((s) => s.replace(/^\[.*\]$/, '1')).join('/'); return r === '/page' ? '/' : r; };
  const rutas = Object.keys(x.workers).map(aRuta);
  return { id, ruta: rutas.find((r) => ['/login', '/registro', '/', '/prohibido'].includes(r)) ?? rutas[0] };
}
class Nav {
  constructor() { this.jar = {}; }
  get cookie() { return Object.entries(this.jar).map(([k, x]) => `${k}=${x}`).join('; '); }
  guardar(r) { for (const c of r.headers.getSetCookie()) { const [kv] = c.split(';'); const i = kv.indexOf('='); const k = kv.slice(0, i), val = kv.slice(i + 1); if (!val) delete this.jar[k]; else this.jar[k] = val; } }
  async get(ruta) { const r = await fetch(BASE + ruta, { headers: { Cookie: this.cookie }, redirect: 'manual' }); this.guardar(r); return r.status; }
  async a(nombre, args) {
    const { id, ruta } = acc(nombre);
    const r = await fetch(BASE + ruta, { method: 'POST', headers: { 'Next-Action': id, 'Content-Type': 'text/plain;charset=UTF-8', Accept: 'text/x-component', Cookie: this.cookie }, body: JSON.stringify(args), redirect: 'manual' });
    this.guardar(r); const t = await r.text(); const l = t.split('\n').find((x) => x.startsWith('1:'));
    return l ? JSON.parse(l.slice(2)) : { crudo: r.status + ' ' + t.slice(0, 150) };
  }
  async s() { return this.a('obtenerCamposSeguros', []); }
  async login(u, c = 'Casino2026*') {
    await this.get('/login'); const e = srp.generateEphemeral();
    const p1 = await this.a('loginPaso1', [u, e.public]);
    const se = srp.deriveSession(e.secret, p1.datos.B, p1.datos.salt, u, srp.derivePrivateKey(p1.datos.salt, u, c));
    return this.a('loginPaso2', [p1.datos.idDesafio, se.proof]);
  }
}
const cred = (u, c) => { const salt = srp.generateSalt(); return { usuario: u, salt, verificador: srp.deriveVerifier(srp.derivePrivateKey(salt, u, c)) }; };
const suf = Date.now().toString(36).slice(-5);

async function main() {
  const ad = new Nav(); v('admin: login', (await ad.login('admin')).ok);

  // ---- Empleados y competencias ----
  const ce = await ad.a('crearEmpleado', [{ nombre: 'Empleado E2E', documento: '7' + String(Date.now()).slice(-8), cargo: 'crupier', salarioMensual: '2500000' }, cred('crup_e2e' + suf, 'Clave-E2E-123'), await ad.s()]);
  v('crearEmpleado (con credenciales SRP derivadas en el cliente)', ce.ok && ce.datos.cargo === 'crupier', j(ce));
  const eid = ce.datos?.id;
  const nuevoLogin = await new Nav().login('crup_e2e' + suf, 'Clave-E2E-123'); v('el empleado nuevo inicia sesión como crupier', nuevoLogin.ok && nuevoLogin.datos.rol === 'crupier', j(nuevoLogin));
  const ae = await ad.a('actualizarEmpleado', [eid, { nombre: 'Empleado E2E Editado', documento: ce.datos.documento, cargo: 'crupier', salarioMensual: '2600000' }, await ad.s()]);
  v('actualizarEmpleado', ae.ok && ae.datos.nombre === 'Empleado E2E Editado', j(ae));
  v('asignarCompetencia', (await ad.a('asignarCompetencia', [eid, 1, await ad.s()])).ok);
  const le = await ad.a('listarEmpleados', []); v('la competencia aparece en el empleado', le.datos.find((x) => x.id === eid)?.competencias.some((c) => c.juegoId === 1));
  v('quitarCompetencia', (await ad.a('quitarCompetencia', [eid, 1, await ad.s()])).ok);
  v('desactivarEmpleado', (await ad.a('desactivarEmpleado', [eid, await ad.s()])).ok);
  const tras = await new Nav().login('crup_e2e' + suf, 'Clave-E2E-123'); v('el empleado desactivado ya no puede iniciar sesión → CA004', err(tras, 'CA004'), j(tras));

  // ---- Mesas ----
  const cm = await ad.a('crearMesa', [{ codigo: 'E2E-' + suf, juegoId: 1, montoMinimo: '100', montoMaximo: '5000' }, await ad.s()]);
  v('crearMesa', cm.ok && cm.datos.codigo === 'E2E-' + suf, j(cm));
  const mid = cm.datos?.id;
  const am = await ad.a('actualizarMesa', [mid, { codigo: 'E2E-' + suf, juegoId: 2, montoMinimo: '200', montoMaximo: '6000' }, await ad.s()]);
  v('actualizarMesa (mesa sin historial: puede cambiar de juego)', am.ok && am.datos.juegoId === 2 && Number(am.datos.montoMinimo) === 200, j(am));
  const malos = await ad.a('crearMesa', [{ codigo: 'E2E-X' + suf, juegoId: 1, montoMinimo: '500', montoMaximo: '100' }, await ad.s()]);
  v('crearMesa con mínimo > máximo → rechazada', malos.ok === false, j(malos));
  const { rows: [conRondas] } = await db.query(`SELECT m.id, m.codigo, m.monto_minimo, m.monto_maximo FROM casino.mesas m WHERE EXISTS (SELECT 1 FROM casino.rondas r WHERE r.mesa_id=m.id) AND m.juego_id = (SELECT id FROM casino.juegos WHERE nombre='Ruleta') LIMIT 1`);
  const c124 = await ad.a('actualizarMesa', [Number(conRondas.id), { codigo: conRondas.codigo, juegoId: 2, montoMinimo: String(Number(conRondas.monto_minimo)), montoMaximo: String(Number(conRondas.monto_maximo)) }, await ad.s()]);
  v('cambiar el juego de una mesa con rondas → CA124', err(c124, 'CA124'), j(c124));
  const c125 = await ad.a('desactivarMesa', [Number(conRondas.id), await ad.s()]);
  v('desactivar una mesa con asignación vigente → CA125', err(c125, 'CA125'), j(c125));

  // ---- Jornada, turno y asignación ----
  const fecha = '2026-12-' + String(1 + (Date.now() % 27)).padStart(2, '0');
  const cj = await ad.a('crearJornada', [fecha, await ad.s()]); v(`crearJornada ${fecha}`, cj.ok, j(cj));
  const jid = cj.datos?.id;
  const ct = await ad.a('crearTurno', [jid, { inicio: `${fecha}T10:00:00-05:00`, fin: `${fecha}T11:30:00-05:00` }, await ad.s()]);
  v('crearTurno de 90 minutos', ct.ok, j(ct));
  const largo = await ad.a('crearTurno', [jid, { inicio: `${fecha}T12:00:00-05:00`, fin: `${fecha}T14:30:00-05:00` }, await ad.s()]);
  v('turno de más de 2 horas → rechazado', largo.ok === false, j(largo));
  const solapa = await ad.a('crearTurno', [jid, { inicio: `${fecha}T11:00:00-05:00`, fin: `${fecha}T12:00:00-05:00` }, await ad.s()]);
  v('turno que se solapa → rechazado', solapa.ok === false, j(solapa));
  const emps = (await ad.a('listarEmpleados', [])).datos;
  const crup = emps.find((e) => e.cargo === 'crupier' && e.activo && e.competencias.some((c) => c.juegoId === 2));
  const sup = emps.find((e) => e.cargo === 'supervisor' && e.activo && e.competencias.some((c) => c.juegoId === 2));
  const ca = await ad.a('crearAsignacion', [{ turnoId: ct.datos.id, mesaId: mid, crupierId: crup.id, supervisorId: sup.id }, await ad.s()]);
  v('crearAsignacion (crupier y supervisor con competencia)', ca.ok, j(ca));
  const sinComp = emps.find((e) => e.cargo === 'crupier' && e.activo && !e.competencias.some((c) => c.juegoId === 2));
  if (sinComp) { const sc = await ad.a('crearAsignacion', [{ turnoId: ct.datos.id, mesaId: mid, crupierId: sinComp.id, supervisorId: sup.id }, await ad.s()]); v('asignar crupier sin competencia en el juego → rechazado', sc.ok === false, j(sc)); }
  const la = await ad.a('listarAsignaciones', [jid]); v('listarAsignaciones de la jornada', la.ok && la.datos.some((x) => x.id === ca.datos?.id));
  v('eliminarAsignacion (sin rondas ni conceptos)', (await ad.a('eliminarAsignacion', [ca.datos.id, await ad.s()])).ok);
  v('eliminarTurno (sin rondas ni conceptos)', (await ad.a('eliminarTurno', [ct.datos.id, await ad.s()])).ok);
  const { rows: [conHist] } = await db.query(`SELECT a.id FROM casino.asignaciones a WHERE EXISTS (SELECT 1 FROM casino.rondas r WHERE r.asignacion_id=a.id) LIMIT 1`);
  const c126 = await ad.a('eliminarAsignacion', [Number(conHist.id), await ad.s()]);
  v('eliminar una asignación con rondas → CA126', err(c126, 'CA126'), j(c126));
  v('desactivarMesa (mesa nueva sin asignaciones vigentes)', (await ad.a('desactivarMesa', [mid, await ad.s()])).ok);

  // ---- Opciones de apuesta ----
  const co = await ad.a('crearOpcion', [2, { nombre: 'Seguro E2E ' + suf, factorPago: '2' }, await ad.s()]);
  v('crearOpcion', co.ok && co.datos.factorPago === '2.00', j(co));
  const ao = await ad.a('actualizarOpcion', [co.datos.id, { nombre: 'Seguro E2E ' + suf, factorPago: '2.5' }, await ad.s()]);
  v('actualizarOpcion (sin apuestas pendientes: cambia el factor)', ao.ok && ao.datos.factorPago === '2.50', j(ao));
  const dup = await ad.a('crearOpcion', [2, { nombre: 'Seguro E2E ' + suf, factorPago: '3' }, await ad.s()]); v('opción duplicada → CA214', err(dup, 'CA214'), j(dup));
  v('desactivarOpcion', (await ad.a('desactivarOpcion', [co.datos.id, await ad.s()])).ok);

  // ---- Riesgo ----
  const u0 = await ad.a('obtenerUmbral', []); v('obtenerUmbral', u0.ok, j(u0));
  const uu = await ad.a('actualizarUmbral', ['999999', await ad.s()]); v('actualizarUmbral', uu.ok && (await ad.a('obtenerUmbral', [])).datos.umbralPerdidaDiaria === '999999.00', j(uu));
  await ad.a('actualizarUmbral', [u0.datos.umbralPerdidaDiaria, await ad.s()]);
  v('listarSuspensiones', (await ad.a('listarSuspensiones', [false])).ok);
  const li = await ad.a('listarInvestigaciones', [true]); v('listarInvestigaciones', li.ok, j(li));
  if (li.ok && li.datos.length) { const ci = await ad.a('cerrarInvestigacion', [li.datos[0].id, 'Revisado en prueba E2E', await ad.s()]); v('cerrarInvestigacion', ci.ok, j(ci)); }
  else console.log('      (no hay investigaciones abiertas; se omite cerrarInvestigacion)');
  const { rows: [empJug] } = await db.query(`SELECT j.empleado_id FROM casino.jugadores j WHERE j.empleado_id IS NOT NULL LIMIT 1`);
  if (empJug) { const ab = await ad.a('registrarAbono', [Number(empJug.empleado_id), '1000', await ad.s()]); v('registrarAbono a empleado que juega', ab.ok && 'deudaRestante' in ab.datos, j(ab)); }
  const ret = await ad.a('registrarRetiro', [1, '10', await ad.s()]); v('registrarRetiro sigue fuera de alcance → CA399', err(ret, 'CA399'), j(ret));

  // ---- Jugador nuevo: editar, historial, pausa, desactivar ----
  const pub = new Nav(); await pub.get('/registro');
  const uj = 'jug_e2e' + suf;
  const rg = await pub.a('registrarJugador', [{ documento: '8' + String(Date.now()).slice(-8), nombre: 'Jugador Pausa', fechaNacimiento: '1990-01-01' }, cred(uj, 'Clave-E2E-123'), await pub.s()]);
  v('registro de jugador para la prueba', rg.ok, j(rg));
  const jid2 = rg.datos.jugadorId;
  v('consignación inicial al jugador nuevo', (await ad.a('registrarConsignacion', [jid2, '50000', await ad.s()])).ok);
  const aj = await ad.a('actualizarJugador', [jid2, { nombre: 'Jugador Pausa Editado', documento: rg.datos.codigo ? '8' + String(Date.now() + 3).slice(-8) : '' }, await ad.s()]);
  v('actualizarJugador', aj.ok && aj.datos.nombre === 'Jugador Pausa Editado', j(aj));
  const oh = await ad.a('obtenerHistorial', [jid2]); v('obtenerHistorial (admin)', oh.ok && oh.datos.movimientos.length === 1, j(oh));
  const jn = new Nav(); await jn.login(uj, 'Clave-E2E-123');
  const sp = await jn.a('solicitarPausa', [await jn.s()]); v('el jugador solicita pausa voluntaria de 24 h', sp.ok && sp.datos.motivo === 'pausa_voluntaria', j(sp));
  const sp2 = await jn.a('solicitarPausa', [await jn.s()]); v('segunda pausa estando en pausa → rechazada', sp2.ok === false, j(sp2));

  // ---- Crupier: anular apuesta, jugador en pausa, anular ronda ----
  const { rows: [r] } = await db.query(`SELECT u.usuario, m.id mesa_id, m.monto_minimo FROM casino.asignaciones a JOIN casino.turnos t ON t.id=a.turno_id JOIN casino.mesas m ON m.id=a.mesa_id JOIN casino.juegos g ON g.id=m.juego_id JOIN casino.empleados e ON e.id=a.crupier_id JOIN casino.usuarios u ON u.id=e.usuario_id WHERE now()>=t.inicio AND now()<t.fin AND g.registro_detallado LIMIT 1`);
  const cr = new Nav(); await cr.login(r.usuario);
  const mm = (await cr.a('misMesasActuales', [])).datos.find((x) => x.mesa.id === Number(r.mesa_id));
  let ronda = mm.rondaAbierta ?? (await cr.a('abrirRonda', [Number(r.mesa_id), await cr.s()])).datos;
  const op = (await cr.a('listarOpciones', [mm.mesa.juegoId])).datos.find((o) => o.activa);
  const bp = await cr.a('buscarJugadorParaApuesta', [rg.datos.codigo]);
  v('el crupier ve al jugador en pausa como no autorizado', bp.ok && bp.datos.puedeApostar === false && !!bp.datos.motivo, j(bp));
  const ap = await cr.a('registrarApuesta', [{ rondaId: ronda.id, jugadorId: jid2, opcionId: op.id, monto: String(Number(r.monto_minimo)) }, await cr.s()]);
  v('apuesta de un jugador en pausa → CA302', err(ap, 'CA302'), j(ap));
  const { rows: [otro] } = await db.query(`SELECT j.id, j.saldo FROM casino.jugadores j WHERE casino.fn_motivo_no_apuesta(j.id) IS NULL AND j.saldo >= 50000 ORDER BY j.id LIMIT 1`);
  const a1 = await cr.a('registrarApuesta', [{ rondaId: ronda.id, jugadorId: Number(otro.id), opcionId: op.id, monto: String(Number(r.monto_minimo)) }, await cr.s()]);
  v('registrar apuesta para anularla', a1.ok, j(a1));
  const an = await cr.a('anularApuesta', [a1.datos.id, await cr.s()]);
  const { rows: [s1] } = await db.query('SELECT saldo FROM casino.jugadores WHERE id=$1', [otro.id]);
  v('anularApuesta devuelve el monto', an.ok && Number(s1.saldo) === Number(otro.saldo), `${j(an)} saldo ${s1.saldo} vs ${otro.saldo}`);
  await cr.a('registrarApuesta', [{ rondaId: ronda.id, jugadorId: Number(otro.id), opcionId: op.id, monto: String(Number(r.monto_minimo)) }, await cr.s()]);
  // La ronda puede traer apuestas pendientes de la semilla: al anular se devuelven todas.
  const { rows: [pend] } = await db.query(`SELECT (SELECT saldo FROM casino.jugadores WHERE id=$2) + coalesce(sum(monto),0) AS esperado
    FROM casino.apuestas WHERE ronda_id=$1 AND jugador_id=$2 AND estado='pendiente'`, [ronda.id, otro.id]);
  const ar = await cr.a('anularRonda', [ronda.id, await cr.s()]);
  const { rows: [s2] } = await db.query('SELECT saldo FROM casino.jugadores WHERE id=$1', [otro.id]);
  v('anularRonda devuelve todas las apuestas pendientes', ar.ok && Number(s2.saldo) === Number(pend.esperado), `${j(ar)} saldo ${s2.saldo} esperado ${pend.esperado}`);

  v('desactivarJugador', (await ad.a('desactivarJugador', [jid2, await ad.s()])).ok);
  const tras2 = await new Nav().login(uj, 'Clave-E2E-123'); v('el jugador desactivado ya no inicia sesión → CA004', err(tras2, 'CA004'), j(tras2));

  console.log(`\nResultado: OK=${ok}  FALLO=${fallo}`);
}
main().catch((e) => { console.error(e); fallo++; }).finally(async () => { await db.end(); process.exit(fallo ? 1 : 0); });
