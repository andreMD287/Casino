import Link from 'next/link';
import { misTurnosSupervisor } from '@/server/acciones/mesas';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { SupervisorConceptos } from '@/components/operacion/supervisor-conceptos';
import { Alerta,EstadoVacio,formatearFecha } from '@/components/comunes/estado';
export default async function Supervisor(){const [r,seguro]=await Promise.all([misTurnosSupervisor(),obtenerCamposSeguros()]);if(!r.ok)return <Alerta mensaje={r.error.mensaje}/>;return <div className="stack"><div className="pagehead"><div><h1>Mis asignaciones</h1><p>Supervisa las mesas y emite tus conceptos al finalizar cada turno</p></div></div>{r.datos.length===0?<EstadoVacio mensaje="No hay asignaciones para supervisar hoy"/>:r.datos.map(a=><section key={a.id} className="panel"><div className="pagehead"><div><h2>{a.mesaCodigo} · {a.juego}</h2><p>Crupier: {a.crupierNombre} · Turno {a.turnoNumero}</p><p>Desde {formatearFecha(a.inicio)} hasta {formatearFecha(a.fin)}</p></div><Link href={`/supervisor/mesas/${a.mesaId}`} className="button secondary">Consultar rondas</Link></div><SupervisorConceptos asignacion={a} seguro={seguro}/></section>)}</div>}
