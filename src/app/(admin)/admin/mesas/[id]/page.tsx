import Link from 'next/link';
import { notFound } from 'next/navigation';
import { listarMesas } from '@/server/acciones/mesas';
import { listarRondas } from '@/server/acciones/rondas';
import { listarApuestas } from '@/server/acciones/apuestas';
import { Alerta, EstadoVacio, EtiquetaEstado,formatearFecha,formatearDinero } from '@/components/comunes/estado';
export default async function MesaDetalle({params}:{params:Promise<{id:string}>}){
 const {id}=await params;const ident=Number(id);if(!Number.isSafeInteger(ident)||ident<=0)notFound();
 const mesas=await listarMesas();if(!mesas.ok)return <Alerta mensaje={mesas.error.mensaje}/>;
 const mesa=mesas.datos.find(m=>m.id===ident);if(!mesa)notFound();
 const r=await listarRondas(ident);if(!r.ok)return <Alerta mensaje={r.error.mensaje}/>;
 const apuestas=await Promise.all(r.datos.slice(0,30).map(x=>listarApuestas(x.id)));
 return <div className="stack"><div className="pagehead"><div><h1>Mesa {mesa.codigo}</h1><p>{mesa.juego} · Mínimo {formatearDinero(mesa.montoMinimo)} · Máximo {formatearDinero(mesa.montoMaximo)}</p></div><Link href="/admin/mesas" className="button secondary">← Volver a mesas</Link></div>
 <section className="panel"><h2>Historial de rondas</h2>{r.datos.length===0?<EstadoVacio mensaje="No hay rondas en esta mesa todavía"/>:<div className="stack">{r.datos.slice(0,30).map((ronda,i)=><div key={ronda.id} style={{borderBottom:'1px solid var(--borde)',paddingBottom:16}}><div className="row-actions"><strong>Ronda #{ronda.numero}</strong><EtiquetaEstado estado={ronda.estado}/><span className="muted">{formatearFecha(ronda.inicio)}</span></div><p className="muted">Resultado: {ronda.resultado.length ? ronda.resultado.map(x=>x.nombre).join(', '):'Sin resultado registrado'}</p>{apuestas[i].ok ? (apuestas[i].datos.length===0 ? <p className="muted">Sin apuestas</p> : <div className="table-scroll"><table className="data-table"><thead><tr><th>Jugador</th><th>Opción</th><th>Monto</th><th>Estado</th><th>Premio</th></tr></thead><tbody>{apuestas[i].datos.map(a=><tr key={a.id}><td>{a.jugadorNombre}</td><td>{a.opcion}</td><td>{formatearDinero(a.monto)}</td><td><EtiquetaEstado estado={a.estado}/></td><td>{a.premio===null?'—':formatearDinero(a.premio)}</td></tr>)}</tbody></table></div>) : <Alerta mensaje={apuestas[i].error.mensaje}/>}</div>)}</div>}</section></div>;
}
