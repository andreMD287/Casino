import { listarJornadas } from '@/server/acciones/mesas';
import { reporteMesaTurno } from '@/server/acciones/rondas';
import { Alerta,EstadoVacio,formatearDinero } from '@/components/comunes/estado';
import Link from 'next/link';
export default async function Reportes({searchParams}:{searchParams:Promise<{jornada?:string}>}){
 const jornadas=await listarJornadas();if(!jornadas.ok)return <Alerta mensaje={jornadas.error.mensaje}/>;const {jornada}=await searchParams;
 const id=Number(jornada??jornadas.datos[0]?.id);const elegida=jornadas.datos.find(j=>j.id===id);
 const reporte=elegida?await reporteMesaTurno(elegida.id):null;
 return <div className="stack"><div className="pagehead"><div><h1>Reportes por mesa y turno</h1><p>Resultado nominal y concepto subjetivo del supervisor</p></div></div><div className="panel"><h2>Seleccionar jornada</h2><div className="row-actions">{jornadas.datos.map(j=><Link className={'button '+(elegida?.id===j.id?'':'secondary')} key={j.id} href={`/admin/reportes?jornada=${j.id}`}>{j.fecha}</Link>)}</div></div><section className="panel"><h2>Resultados de la jornada</h2>{!elegida?<EstadoVacio mensaje="Aún no hay jornadas registradas"/>:!reporte?<EstadoVacio mensaje="Selecciona una jornada"/>:!reporte.ok?<Alerta mensaje={reporte.error.mensaje}/>:reporte.datos.length===0?<EstadoVacio mensaje="Esta jornada no tiene reportes todavía"/>:<div className="table-scroll"><table className="data-table"><thead><tr><th>Mesa</th><th>Turno</th><th>Crupier</th><th>Supervisor</th><th>Apostado</th><th>Premios</th><th>Resultado nominal</th><th>Concepto</th></tr></thead><tbody>{reporte.datos.map((f,i)=><tr key={`${f.mesaCodigo}-${f.turnoNumero}-${i}`}><td>{f.mesaCodigo}</td><td>{f.turnoNumero}</td><td>{f.crupier}</td><td>{f.supervisor}</td><td>{formatearDinero(f.totalApostado)}</td><td>{formatearDinero(f.totalPremios)}</td><td>{formatearDinero(f.resultadoNominal)}</td><td>{f.concepto??'Sin concepto'}</td></tr>)}</tbody></table></div>}</section></div>
}
