import Link from 'next/link';
import { listarSuspensiones, listarInvestigaciones } from '@/server/acciones/riesgo';
import { listarMesas } from '@/server/acciones/mesas';
import { Alerta, EstadoVacio, EtiquetaEstado, formatearFecha } from '@/components/comunes/estado';
export default async function AdminInicio(){
 const [sus, inv, mesas]=await Promise.all([listarSuspensiones(true),listarInvestigaciones(true),listarMesas()]);
 const errores=[sus,inv,mesas].filter(x=>!x.ok).map(x=>x.ok?'':x.error.mensaje);
 return <div className="stack"><div className="pagehead"><div><h1>Panel de administración</h1><p>Resumen de operación y control del casino</p></div><span className="badge">Datos del sistema</span></div>
 {errores.length>0&&<Alerta mensaje={errores.join(' · ')}/>}
 <div className="three">
   <div className="stat"><span className="label">Mesas registradas activas</span><strong>{mesas.ok?mesas.datos.filter(m=>m.activa).length:'—'}</strong><small>Gestiona su configuración y límites</small></div>
   <div className="stat"><span className="label">Jugadores suspendidos</span><strong>{sus.ok?sus.datos.length:'—'}</strong><small>Suspensiones que requieren seguimiento</small></div>
   <div className="stat"><span className="label">Investigaciones abiertas</span><strong>{inv.ok?inv.datos.length:'—'}</strong><small>Consulta y resolución administrativa</small></div>
 </div>
 <div className="two"><section className="panel"><h2>Alertas y seguimiento</h2>{sus.ok && inv.ok && sus.datos.length===0 && inv.datos.length===0 ? <EstadoVacio mensaje="No hay suspensiones ni investigaciones abiertas"/> : <div className="table-scroll"><table className="data-table"><thead><tr><th>Tipo</th><th>Jugador</th><th>Información</th><th>Estado</th></tr></thead><tbody>
   {sus.ok&&sus.datos.slice(0,6).map(s=><tr key={'s'+s.id}><td>Suspensión</td><td>{s.jugadorNombre}</td><td>{s.motivo}</td><td><EtiquetaEstado estado="Suspendido"/></td></tr>)}
   {inv.ok&&inv.datos.slice(0,6).map(i=><tr key={'i'+i.id}><td>Investigación</td><td>{i.jugadorNombre}</td><td>{formatearFecha(i.abiertaEn)}</td><td><EtiquetaEstado estado="Investigación"/></td></tr>)}
 </tbody></table></div>}<p style={{marginTop:17}}><Link href="/admin/riesgo" className="textlink">Abrir gestión de riesgo →</Link></p></section>
 <section className="panel"><h2>Accesos rápidos</h2><div className="stack">
   <Link href="/admin/empleados" className="button secondary">Administrar empleados →</Link>
   <Link href="/admin/mesas" className="button secondary">Gestionar mesas →</Link>
   <Link href="/admin/turnos" className="button secondary">Jornadas y turnos →</Link>
   <Link href="/admin/jugadores" className="button secondary">Consultar jugadores y saldo →</Link>
 </div></section></div>
 </div>;
}
