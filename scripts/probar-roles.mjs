// Prueba de punta a punta contra la app real (MODO_MOCK=0) — André.
// Uso: ./db/run_all.sh  →  npm run build && npm start -- -p 3100  →  node scripts/probar-roles.mjs
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
const admin = new Pool({ database: 'casino', max: 1 });

let ok = 0, fallo = 0;
const v = (desc, cond, det = '') => { if (cond) { ok++; console.log(`[OK] ${desc}`); } else { fallo++; console.log(`[FALLO] ${desc} ${det}`); } };

// id de la acción y una página que la registra
function acc(nombre) {
  const e = Object.entries(manifest.node).filter(([, x]) => x.exportedName === nombre);
  if (!e.length) throw new Error('acción no encontrada: ' + nombre);
  const [id, x] = e[0];
  const aRuta = (w) => { const r = '/' + w.replace(/^app\//, '').replace(/\/page$/, '').split('/').filter((s) => !/^\(.*\)$/.test(s)).map((s) => s.replace(/^\[.*\]$/, '1')).join('/'); return r === '/page' ? '/' : r; };
  const rutas = Object.keys(x.workers).map(aRuta);
  const publica = rutas.find((r) => ['/login', '/registro', '/', '/prohibido'].includes(r));
  return { id, ruta: publica ?? rutas[0] };
}

class Navegador {
  constructor(n) { this.n = n; this.jar = {}; }
  get cookie() { return Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '); }
  guardar(r) { for (const c of r.headers.getSetCookie()) { const [kv] = c.split(';'); const i = kv.indexOf('='); const k = kv.slice(0, i); const val = kv.slice(i + 1); if (val === '' || /Max-Age=0|Expires=Thu, 01 Jan 1970/i.test(c)) delete this.jar[k]; else this.jar[k] = val; } }
  async get(ruta) { const r = await fetch(BASE + ruta, { headers: { Cookie: this.cookie }, redirect: 'manual' }); this.guardar(r); const t = r.status === 200 ? await r.text() : ''; const meta = (t.match(/__next-page-redirect" http-equiv="refresh" content="\d+;url=([^"]+)"/) || [])[1]; return { status: r.status, destino: r.headers.get('location') ?? meta ?? null, html: t }; }
  async accion(nombre, args) {
    const { id, ruta } = acc(nombre);
    const r = await fetch(BASE + ruta, { method: 'POST', headers: { 'Next-Action': id, 'Content-Type': 'text/plain;charset=UTF-8', Accept: 'text/x-component', Cookie: this.cookie }, body: JSON.stringify(args), redirect: 'manual' });
    this.guardar(r);
    const t = await r.text();
    const l = t.split('\n').find((x) => x.startsWith('1:'));
    return l ? JSON.parse(l.slice(2)) : { crudo: r.status + ' ' + t.slice(0, 150) };
  }
  async seguro() { return this.accion('obtenerCamposSeguros', []); }
  async login(usuario, clave = 'Casino2026*') {
    await this.get('/login');
    const e = srp.generateEphemeral();
    const p1 = await this.accion('loginPaso1', [usuario, e.public]);
    if (!p1.ok) return p1;
    const s = srp.deriveSession(e.secret, p1.datos.B, p1.datos.salt, usuario, srp.derivePrivateKey(p1.datos.salt, usuario, clave));
    const p2 = await this.accion('loginPaso2', [p1.datos.idDesafio, s.proof]);
    if (p2.ok) srp.verifySession(e.public, s, p2.datos.M2);
    return p2;
  }
}
const pagina = async (nav, ruta, desc) => { const r = await nav.get(ruta); v(`${nav.n}: ${desc} ${ruta} → 200`, r.status === 200 && !/Error interno|Application error/.test(r.html) && !r.destino, `(status ${r.status} ${r.destino ?? ''})`); return r; };

async function main() {
  // ---------------- ADMINISTRADOR ----------------
  const ad = new Navegador('admin');
  const la = await ad.login('admin');
  v('admin: login SRP real', la.ok && la.datos.rol === 'administrador', JSON.stringify(la));
  for (const r of ['/admin', '/admin/empleados', '/admin/mesas', '/admin/turnos', '/admin/jugadores', '/admin/riesgo', '/admin/opciones', '/admin/reportes'])
    await pagina(ad, r, 'página');
  const emp = await ad.accion('listarEmpleados', []); v('admin: listarEmpleados', emp.ok && emp.datos.length >= 7, JSON.stringify(emp).slice(0, 120));
  const mes = await ad.accion('listarMesas', []); v('admin: listarMesas', mes.ok && mes.datos.length >= 3);
  const jug = await ad.accion('listarJugadores', []); v('admin: listarJugadores', jug.ok && jug.datos.length >= 5);
  await pagina(ad, `/admin/mesas/${mes.datos[0].id}`, 'detalle mesa');
  await pagina(ad, `/admin/jugadores/${jug.datos[0].id}`, 'detalle jugador');
  await pagina(ad, `/admin/empleados/${emp.datos[0].id}`, 'detalle empleado');
  const jor = await ad.accion('listarJornadas', []);
  if (jor.ok && jor.datos.length) { const rep = await ad.accion('reporteMesaTurno', [jor.datos[0].id]); v('admin: reporteMesaTurno', rep.ok, JSON.stringify(rep).slice(0, 120)); }
  const ops = await ad.accion('listarOpciones', [1]); v('admin: listarOpciones', ops.ok && ops.datos.length > 0);
  const objetivo = jug.datos.find((j) => j.estado === 'Activo') ?? jug.datos[0];
  const antes = Number(objetivo.saldo);
  const cons = await ad.accion('registrarConsignacion', [objetivo.id, '125.50', await ad.seguro()]);
  v('admin: registrarConsignacion 125.50 (saldo inicial en fichas)', cons.ok && Number(cons.datos.saldoResultante) === antes + 125.5, JSON.stringify(cons).slice(0, 160));
  const firmaMala = { ...(await ad.seguro()), firma: '0'.repeat(64) };
  const cm = await ad.accion('registrarConsignacion', [objetivo.id, '10', firmaMala]);
  v('admin: formulario con firma alterada → CA007', !cm.ok && cm.error.codigo === 'CA007', JSON.stringify(cm));

  // ---------------- CRUPIERES (cada uno en su mesa del turno vigente) ----------------
  const { rows: asig } = await admin.query(`
    SELECT u.usuario, m.id mesa_id, m.codigo, jg.nombre juego, m.monto_minimo
    FROM casino.asignaciones a JOIN casino.turnos t ON t.id=a.turno_id JOIN casino.mesas m ON m.id=a.mesa_id
    JOIN casino.juegos jg ON jg.id=m.juego_id JOIN casino.empleados e ON e.id=a.crupier_id JOIN casino.usuarios u ON u.id=e.usuario_id
    WHERE now() >= t.inicio AND now() < t.fin ORDER BY m.codigo`);
  v('hay asignaciones en el turno vigente', asig.length > 0, '(correr db/demo/turno_actual.sql)');
  const { rows: apostadores } = await admin.query(`SELECT j.codigo FROM casino.jugadores j WHERE casino.fn_motivo_no_apuesta(j.id) IS NULL AND j.saldo >= 20000 ORDER BY j.id`);
  for (const a of asig.map((x) => ({ ...x, mesa_id: Number(x.mesa_id) }))) {
    const cr = new Navegador(a.usuario);
    const l = await cr.login(a.usuario);
    v(`${a.usuario}: login SRP real (rol crupier)`, l.ok && l.datos.rol === 'crupier', JSON.stringify(l));
    await pagina(cr, '/crupier', 'página');
    await pagina(cr, `/crupier/mesas/${a.mesa_id}`, `mesa ${a.codigo}`);
    const mm = await cr.accion('misMesasActuales', []);
    const mia = mm.ok && mm.datos.find((x) => x.mesa.id === a.mesa_id);
    v(`${a.usuario}: misMesasActuales incluye ${a.codigo}`, !!mia, JSON.stringify(mm).slice(0, 150));
    let ronda = mia?.rondaAbierta;
    if (!ronda) { const ab = await cr.accion('abrirRonda', [a.mesa_id, await cr.seguro()]); v(`${a.usuario}: abrirRonda en ${a.codigo}`, ab.ok, JSON.stringify(ab)); ronda = ab.datos; }
    else { const ab2 = await cr.accion('abrirRonda', [a.mesa_id, await cr.seguro()]); v(`${a.usuario}: segunda ronda abierta en ${a.codigo} → CA208`, !ab2.ok && ab2.error.codigo === 'CA208', JSON.stringify(ab2)); }
    const bj = await cr.accion('buscarJugadorParaApuesta', [apostadores[0].codigo]);
    v(`${a.usuario}: buscarJugadorParaApuesta ${apostadores[0].codigo}`, bj.ok && bj.datos.puedeApostar, JSON.stringify(bj).slice(0, 150));
    const opc = (await cr.accion('listarOpciones', [mia.mesa.juegoId])).datos.filter((o) => o.activa);
    const monto = String(Number(a.monto_minimo));
    if (a.juego === 'Póker') {
      const r1 = await cr.accion('registrarApuestaResuelta', [{ rondaId: ronda.id, jugadorId: bj.datos.jugadorId, opcionId: opc[0].id, monto, ganada: true }, await cr.seguro()]);
      v(`${a.usuario}: registrarApuestaResuelta (póker, ganada)`, r1.ok && r1.datos.estado === 'ganada', JSON.stringify(r1).slice(0, 160));
      const c = await cr.accion('cerrarRonda', [ronda.id, [], await cr.seguro()]);
      v(`${a.usuario}: cerrarRonda póker sin resultado`, c.ok, JSON.stringify(c));
    } else {
      const op = a.juego === 'Ruleta' ? opc.find((o) => o.nombre === 'Rojo') : opc.find((o) => o.nombre === 'Mano ganadora');
      const r1 = await cr.accion('registrarApuesta', [{ rondaId: ronda.id, jugadorId: bj.datos.jugadorId, opcionId: op.id, monto }, await cr.seguro()]);
      v(`${a.usuario}: registrarApuesta ${op.nombre} por ${monto}`, r1.ok && r1.datos.estado === 'pendiente', JSON.stringify(r1).slice(0, 160));
      const bajo = await cr.accion('registrarApuesta', [{ rondaId: ronda.id, jugadorId: bj.datos.jugadorId, opcionId: op.id, monto: '1' }, await cr.seguro()]);
      v(`${a.usuario}: monto menor al mínimo → CA205`, !bajo.ok && bajo.error.codigo === 'CA205', JSON.stringify(bajo));
      const la2 = await cr.accion('listarApuestas', [ronda.id]); v(`${a.usuario}: listarApuestas de la ronda`, la2.ok && la2.datos.some((x) => x.id === r1.datos.id));
      let gan;
      if (a.juego === 'Ruleta') {
        const inc = await cr.accion('cerrarRonda', [ronda.id, [opc.find((o) => o.nombre === 'Pleno 17').id, opc.find((o) => o.nombre === 'Rojo').id], await cr.seguro()]);
        v(`${a.usuario}: cerrar ruleta con 17 + Rojo → CA217`, !inc.ok && inc.error.codigo === 'CA217', JSON.stringify(inc));
        gan = [opc.find((o) => o.nombre === 'Pleno 3').id];   // 3 = rojo: la apuesta a Rojo gana
      } else gan = [op.id];
      const c = await cr.accion('cerrarRonda', [ronda.id, gan, await cr.seguro()]);
      v(`${a.usuario}: cerrarRonda ${a.codigo} con resumen`, c.ok && c.datos.ganadas >= 1, JSON.stringify(c));
      const ap = await cr.accion('listarApuestas', [ronda.id]);
      const mia2 = ap.datos.find((x) => x.id === r1.datos.id);
      v(`${a.usuario}: la apuesta quedó ganada con premio = monto × factor`, mia2?.estado === 'ganada' && Number(mia2.premio) === Number(monto) * Number(op.factorPago), JSON.stringify(mia2));
    }
    const fuera = await cr.accion('listarEmpleados', []);
    v(`${a.usuario}: acción de administrador (listarEmpleados) → CA002`, !fuera.ok && fuera.error.codigo === 'CA002', JSON.stringify(fuera));
    const pa = await cr.get('/admin'); v(`${a.usuario}: /admin → /prohibido`, /prohibido/.test(pa.destino ?? ''), `${pa.status} ${pa.destino}`);
  }

  // ---------------- SUPERVISOR ----------------
  const sp = new Navegador('supervisor1');
  const ls = await sp.login('supervisor1');
  v('supervisor1: login SRP real', ls.ok && ls.datos.rol === 'supervisor', JSON.stringify(ls));
  await pagina(sp, '/supervisor', 'página');
  const mt = await sp.accion('misTurnosSupervisor', []); v('supervisor1: misTurnosSupervisor', mt.ok, JSON.stringify(mt).slice(0, 120));
  if (mt.ok && mt.datos.length) await pagina(sp, `/supervisor/mesas/${mt.datos[0].mesaId}`, 'mesa supervisada');
  const pend = mt.ok ? mt.datos.find((x) => !x.concepto && Date.parse(x.fin) < Date.now()) : null;
  if (pend) { const ec = await sp.accion('emitirConcepto', [pend.id, 'Comportamiento neutro', 'Prueba E2E', await sp.seguro()]); v('supervisor1: emitirConcepto en turno terminado', ec.ok, JSON.stringify(ec).slice(0, 150)); }
  else console.log('      (supervisor1 no tiene turnos terminados sin concepto; se omite emitirConcepto)');
  const rs = await sp.accion('listarRondas', [Number(asig[0]?.mesa_id ?? 1)]); v('supervisor1: listarRondas', rs.ok);
  const sx = await sp.accion('abrirRonda', [1, await sp.seguro()]); v('supervisor1: abrirRonda → CA002', !sx.ok && sx.error.codigo === 'CA002', JSON.stringify(sx));

  // ---------------- JUGADOR ----------------
  const jg = new Navegador('jugador1');
  const lj = await jg.login('jugador1');
  v('jugador1: login SRP real', lj.ok && lj.datos.rol === 'jugador', JSON.stringify(lj));
  await pagina(jg, '/jugador', 'página');
  const mh = await jg.accion('miHistorial', []); v('jugador1: miHistorial con apuestas y movimientos', mh.ok && mh.datos.movimientos.length > 0, JSON.stringify(mh).slice(0, 150));
  const ja = await jg.accion('abrirRonda', [1, await jg.seguro()]); v('jugador1: abrirRonda (rol no permitido) → CA002', !ja.ok && ja.error.codigo === 'CA002', JSON.stringify(ja));
  const jp = await jg.get('/admin'); v('jugador1: /admin → /prohibido', /prohibido/.test(jp.destino ?? ''), `${jp.status} ${jp.destino}`);
  const jc = await jg.get('/crupier'); v('jugador1: /crupier → /prohibido', /prohibido/.test(jc.destino ?? ''), `${jc.status} ${jc.destino}`);
  await jg.accion('cerrarSesion', []);
  const tras = await jg.get('/jugador'); v('jugador1: después de cerrar sesión, /jugador → /login', tras.status === 307 && /login/.test(tras.destino ?? ''), `${tras.status} ${tras.destino}`);
  const mal = await new Navegador('x').login('jugador1', 'otra-clave'); v('login con clave incorrecta → CA004', !mal.ok && mal.error.codigo === 'CA004', JSON.stringify(mal));

  // ---------------- REGISTRO PÚBLICO ----------------
  const nuevo = new Navegador('nuevo');
  await pagina(nuevo, '/registro', 'página pública');
  const u = 'e2e_' + Date.now().toString(36);
  const salt = srp.generateSalt();
  const cred = { usuario: u, salt, verificador: srp.deriveVerifier(srp.derivePrivateKey(salt, u, 'Clave-E2E-123')) };
  const rg = await nuevo.accion('registrarJugador', [{ documento: String(Date.now()).slice(-10), nombre: 'Jugador E2E', fechaNacimiento: '1995-05-05' }, cred, await nuevo.seguro()]);
  v('registro público de jugador (canal anónimo + firma)', rg.ok && /^J-\d{6}$/.test(rg.datos.codigo), JSON.stringify(rg));
  const menor = await nuevo.accion('registrarJugador', [{ documento: String(Date.now() + 7).slice(-10), nombre: 'Menor E2E', fechaNacimiento: '2015-01-01' }, { ...cred, usuario: u + 'm' }, await nuevo.seguro()]);
  v('registro de un menor de edad → rechazado', !menor.ok, JSON.stringify(menor));
  const ln = await nuevo.login(u, 'Clave-E2E-123'); v('el jugador recién registrado inicia sesión', ln.ok && ln.datos.rol === 'jugador', JSON.stringify(ln));

  console.log(`\nResultado: OK=${ok}  FALLO=${fallo}`);
}
main().catch((e) => { console.error(e); fallo++; }).finally(async () => { await admin.end(); process.exit(fallo ? 1 : 0); });
