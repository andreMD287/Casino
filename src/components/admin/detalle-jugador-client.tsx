'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { registrarConsignacion } from '@/server/acciones/riesgo';
import type { Historial,CamposSeguros } from '@/lib/contrato';
import { Alerta,EstadoVacio,EtiquetaEstado,formatearDinero,formatearFecha } from '@/components/comunes/estado';
import { Confirmar } from '@/components/comunes/confirmar';

type Pestaña='apuestas'|'movimientos'|'suspensiones'|'investigaciones';
export function DetalleJugadorClient({historial,seguro}:{historial:Historial;seguro:CamposSeguros}){
 const router=useRouter();const {jugador}=historial;
 const [tab,setTab]=useState<Pestaña>('movimientos');const [monto,setMonto]=useState('');const [modal,setModal]=useState(false);const [ocupado,setOcupado]=useState(false);const [error,setError]=useState<string|null>(null);const [exito,setExito]=useState<string|null>(null);
 const valido=/^\d+(?:\.\d{1,2})?$/.test(monto)&&Number(monto)>0;
 async function ejecutar(){if(!valido||ocupado)return;setOcupado(true);setError(null);setExito(null);try{
  // Este endpoint lo publica Andrés; si aún es el stub CA399 se conserva el error real.
  const r=await registrarConsignacion(jugador.id,monto,seguro);
  if(!r.ok){setError(r.error.codigo==='CA007'?'El formulario venció, recarga la página.':r.error.mensaje);setModal(false);return;}
  setModal(false);setMonto('');setTab('movimientos');setExito(`Consignación registrada. Nuevo saldo: ${formatearDinero(r.datos.saldoResultante)}.`);
  // Relee saldo e historial desde el servidor, no los calcula localmente.
  router.refresh();
 }catch{setError('No se pudo completar la consignación. No se modificó el saldo en la interfaz.');setModal(false);}finally{setOcupado(false);}}
 return <div className="stack"><div className="pagehead"><div><h1>{jugador.nombre}</h1><p>{jugador.codigo} · Documento {jugador.documento}</p></div><Link href="/admin/jugadores" className="button secondary">← Volver a jugadores</Link></div>
 <div className="three"><div className="stat"><span className="label">Saldo actual en fichas</span><strong style={{fontSize:28}}>{formatearDinero(jugador.saldo)}</strong></div><div className="stat"><span className="label">Estado del jugador</span><p style={{marginTop:14}}><EtiquetaEstado estado={jugador.estado}/></p></div><div className="stat"><span className="label">Cuenta de empleado</span><strong style={{fontSize:23}}>{jugador.esEmpleado?'Sí':'No'}</strong>{historial.deudaEmpleado!==null&&<small>Deuda: {formatearDinero(historial.deudaEmpleado)}</small>}</div></div>
 <section className="panel"><h2>Consignación administrativa</h2><p className="muted">El administrador puede cargar fichas al jugador. Toda consignación queda registrada en sus movimientos.</p>
 <div className="searchrow"><div><label htmlFor="monto-consignacion">Monto a consignar</label><input id="monto-consignacion" type="text" inputMode="decimal" value={monto} onChange={e=>setMonto(e.target.value.replace(',','.'))} placeholder="Ej. 50000.00" aria-describedby="ayuda-monto" disabled={!jugador.activo||ocupado}/><p className="hint" id="ayuda-monto">Mayor que cero y máximo dos decimales. El servidor valida el valor.</p></div><button className="button" type="button" disabled={!valido||!jugador.activo||ocupado} onClick={()=>setModal(true)}>Consignar fichas</button></div>
 {!jugador.activo&&<Alerta mensaje="Este jugador está inactivo: no puede recibir consignaciones." tipo="info"/>}<Alerta mensaje={error}/><Alerta mensaje={exito} tipo="success"/>{error==='El formulario venció, recarga la página.'&&<button className="button secondary" type="button" onClick={()=>window.location.reload()}>Recargar formulario</button>}</section>
 <section className="panel"><h2>Historial del cliente</h2><div className="tabs" role="tablist" aria-label="Secciones del historial">{(['apuestas','movimientos','suspensiones','investigaciones'] as Pestaña[]).map(t=><button key={t} role="tab" type="button" aria-selected={tab===t} onClick={()=>setTab(t)}>{t[0].toUpperCase()+t.slice(1)}</button>)}</div>
 {tab==='movimientos'&&(historial.movimientos.length===0?<EstadoVacio mensaje="No hay movimientos todavía"/>:<div className="table-scroll"><table className="data-table"><thead><tr><th>Fecha</th><th>Movimiento</th><th>Monto</th><th>Saldo resultante</th></tr></thead><tbody>{historial.movimientos.map(m=><tr key={m.id}><td>{formatearFecha(m.fecha)}</td><td>{m.tipo}</td><td>{formatearDinero(m.monto)}</td><td>{formatearDinero(m.saldoResultante)}</td></tr>)}</tbody></table></div>)}
 {tab==='apuestas'&&(historial.apuestas.length===0?<EstadoVacio mensaje="No hay apuestas todavía"/>:<div className="table-scroll"><table className="data-table"><thead><tr><th>Ronda</th><th>Opción</th><th>Monto</th><th>Estado</th><th>Premio</th></tr></thead><tbody>{historial.apuestas.map(a=><tr key={a.id}><td>{a.mesaCodigo} · #{a.rondaNumero}</td><td>{a.opcion}</td><td>{formatearDinero(a.monto)}</td><td><EtiquetaEstado estado={a.estado}/></td><td>{a.premio===null?'—':formatearDinero(a.premio)}</td></tr>)}</tbody></table></div>)}
 {tab==='suspensiones'&&(historial.suspensiones.length===0?<EstadoVacio mensaje="No hay suspensiones registradas"/>:<div className="table-scroll"><table className="data-table"><thead><tr><th>Motivo</th><th>Inicio</th><th>Hasta</th><th>Estado</th></tr></thead><tbody>{historial.suspensiones.map(s=><tr key={s.id}><td>{s.motivo}</td><td>{formatearFecha(s.inicio)}</td><td>{s.fin?formatearFecha(s.fin):'Sin fecha definida'}</td><td><EtiquetaEstado estado={s.activa?'Suspendido':'Finalizada'}/></td></tr>)}</tbody></table></div>)}
 {tab==='investigaciones'&&(historial.investigaciones.length===0?<EstadoVacio mensaje="No hay investigaciones registradas"/>:<div className="table-scroll"><table className="data-table"><thead><tr><th>Apertura</th><th>Cierre</th><th>Resolución</th></tr></thead><tbody>{historial.investigaciones.map(i=><tr key={i.id}><td>{formatearFecha(i.abiertaEn)}</td><td>{i.cerradaEn?formatearFecha(i.cerradaEn):'Abierta'}</td><td>{i.resolucion??'Pendiente'}</td></tr>)}</tbody></table></div>)}
 </section>
 {modal&&<Confirmar titulo="Confirmar consignación" descripcion={`¿Deseas consignar ${formatearDinero(monto)} a ${jugador.nombre} (${jugador.codigo})? Esta operación quedará registrada en su historial.`} confirmacion="Confirmar consignación" esperando={ocupado} onCerrar={()=>setModal(false)} onConfirmar={ejecutar}/>}
 </div>;
}
