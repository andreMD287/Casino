'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { abrirRonda,cerrarRonda,anularRonda } from '@/server/acciones/rondas';
import { buscarJugadorParaApuesta,registrarApuesta,registrarApuestaResuelta,anularApuesta } from '@/server/acciones/apuestas';
import { Alerta,EtiquetaEstado,formatearDinero,formatearFecha,EstadoVacio } from '@/components/comunes/estado';
import { Confirmar } from '@/components/comunes/confirmar';
import type { MesaCrupier,Ronda,Apuesta,OpcionApuesta,JugadorParaApuesta,CamposSeguros } from '@/lib/contrato';

type Accion='abrir'|'anularRonda'|'cerrar'|'anularApuesta';
export function CrupierMesaClient({asignacion,rondas,apuestas,opciones,seguro}:{asignacion:MesaCrupier;rondas:Ronda[];apuestas:Apuesta[];opciones:OpcionApuesta[];seguro:CamposSeguros}){
 const router=useRouter();const {mesa}=asignacion;const ronda=asignacion.rondaAbierta;
 const [codigo,setCodigo]=useState('');const [jugador,setJugador]=useState<JugadorParaApuesta|null>(null);const [opcion,setOpcion]=useState('');const [monto,setMonto]=useState('');const [ganada,setGanada]=useState(false);
 const [ganadoras,setGanadoras]=useState<number[]>([]);const [esperando,setEsperando]=useState(false);const [error,setError]=useState<string|null>(null);const [mensaje,setMensaje]=useState<string|null>(null);const [resumen,setResumen]=useState<string|null>(null);const [confirmar,setConfirmar]=useState<{accion:Accion;id?:number}|null>(null);
 async function buscar(e:React.FormEvent<HTMLFormElement>){e.preventDefault();setEsperando(true);setError(null);setJugador(null);try{const r=await buscarJugadorParaApuesta(codigo.trim());if(!r.ok){setError(r.error.mensaje);return;}setJugador(r.datos);}catch{setError('No se pudo consultar el jugador.');}finally{setEsperando(false);}}
 async function enviarApuesta(e:React.FormEvent<HTMLFormElement>){e.preventDefault();if(!ronda||!jugador||!opcion||esperando)return;setEsperando(true);setError(null);setMensaje(null);try{
  const datos={rondaId:ronda.id,jugadorId:jugador.jugadorId,opcionId:Number(opcion),monto};
  const r=mesa.registroDetallado?await registrarApuesta(datos,seguro):await registrarApuestaResuelta({...datos,ganada},seguro);
  if(!r.ok){setError(r.error.mensaje);return;}
  setMensaje('Apuesta registrada correctamente.');setMontaVacio();router.refresh();
 }catch{setError('No se pudo registrar la apuesta.');}finally{setEsperando(false);}}
 function setMontaVacio(){setMonto('');setOpcion('');}
 async function ejecutar(){if(!confirmar||esperando)return;setEsperando(true);setError(null);setMensaje(null);try{
  const r=confirmar.accion==='abrir' ? await abrirRonda(mesa.id,seguro)
   : confirmar.accion==='anularRonda' ? await anularRonda(ronda!.id,seguro)
   : confirmar.accion==='anularApuesta' ? await anularApuesta(confirmar.id!,seguro)
   : await cerrarRonda(ronda!.id,mesa.registroDetallado?ganadoras:[],seguro);
  if(!r.ok){setError(r.error.mensaje);setConfirmar(null);return;}
  if(confirmar.accion==='cerrar' && r.datos && typeof r.datos === 'object' && 'ganadas' in r.datos){const s=r.datos;setResumen(`Ronda cerrada: ${s.ganadas} ganadas, ${s.perdidas} perdidas. Premios ${formatearDinero(s.totalPremios)}. Resultado del casino: ${formatearDinero(s.resultadoCasino)}.`);}
  setMensaje('Operación realizada correctamente.');setConfirmar(null);router.refresh();
 }catch{setError('No se pudo completar la operación.');setConfirmar(null);}finally{setEsperando(false);}}
 const esRuleta=mesa.juego.toLowerCase().includes('ruleta');const plenos=opciones.filter(o=>/^pleno\s+\d+$/i.test(o.nombre));
 function toggleGanadora(id:number){if(esRuleta){setGanadoras([id]);return;}setGanadoras(prev=>prev.includes(id)?prev.filter(x=>x!==id):[...prev,id]);}
 return <div className="stack"><div className="pagehead"><div><h1>Mesa {mesa.codigo}</h1><p>{mesa.juego} · Turno {formatearFecha(asignacion.inicioTurno)} – {formatearFecha(asignacion.finTurno)}</p></div><EtiquetaEstado estado={ronda?'abierta':'sin ronda abierta'}/></div>
 <div className="three"><div className="stat"><span className="label">Mínimo por jugada</span><strong style={{fontSize:26}}>{formatearDinero(mesa.montoMinimo)}</strong></div><div className="stat"><span className="label">Máximo por jugada</span><strong style={{fontSize:26}}>{formatearDinero(mesa.montoMaximo)}</strong></div><div className="stat"><span className="label">Rondas registradas</span><strong>{rondas.length}</strong></div></div>
 <Alerta mensaje={error}/><Alerta mensaje={mensaje} tipo="success"/>{resumen&&<Alerta mensaje={resumen} tipo="success"/>}
 {!ronda ? <section className="panel"><h2>No hay ronda abierta</h2><p>Puedes iniciar una nueva ronda si eres el crupier asignado en el turno vigente.</p><button className="button" disabled={esperando} onClick={()=>setConfirmar({accion:'abrir'})}>Abrir ronda</button></section> : <>
 <section className="panel"><h2>Ronda #{ronda.numero} · Registrar apuesta</h2><form onSubmit={buscar} className="searchrow"><div><label htmlFor="codigo-jugador">Código de jugador</label><input id="codigo-jugador" value={codigo} onChange={e=>{setCodigo(e.target.value);setJugador(null);}} placeholder="Ej. J-000001" required /></div><button className="button secondary" type="submit" disabled={esperando}>Buscar jugador</button></form>
 {jugador&&<div className="notice"><strong>{jugador.nombre}</strong> · Saldo: {formatearDinero(jugador.saldo)} · {jugador.puedeApostar?'Autorizado para apostar':`No autorizado: ${jugador.motivo??'Consulta con administración'}`}</div>}
 <form onSubmit={enviarApuesta}><div className="formgrid"><div className="field"><label htmlFor="opcion-apuesta">Opción de apuesta</label><select id="opcion-apuesta" value={opcion} onChange={e=>setOpcion(e.target.value)} required><option value="">Selecciona una opción</option>{opciones.filter(o=>o.activa).map(o=><option key={o.id} value={o.id}>{o.nombre} · Factor {o.factorPago}</option>)}</select></div><div className="field"><label htmlFor="monto-apuesta">Monto</label><input id="monto-apuesta" inputMode="decimal" pattern="[0-9]+([.,][0-9]{1,2})?" required value={monto} onChange={e=>setMonto(e.target.value.replace(',','.'))} placeholder="0.00"/></div></div>{!mesa.registroDetallado&&<div className="field"><label htmlFor="resultado-poker">Resultado del jugador (póker)</label><select id="resultado-poker" value={ganada?'ganada':'perdida'} onChange={e=>setGanada(e.target.value==='ganada')}><option value="perdida">Perdida</option><option value="ganada">Ganada</option></select></div>}
 <p className="hint">Los límites, saldo y suspensiones son validados por el servidor. En póker se registra una apuesta ya resuelta.</p><button className="button" disabled={esperando||!jugador?.puedeApostar||!opcion}>Registrar apuesta</button></form></section>
 <section className="panel"><h2>Apuestas de la ronda</h2>{apuestas.length===0?<EstadoVacio mensaje="Esta ronda no tiene apuestas registradas todavía"/>:<div className="table-scroll"><table className="data-table"><thead><tr><th>Jugador</th><th>Opción</th><th>Monto</th><th>Estado</th><th>Acción</th></tr></thead><tbody>{apuestas.map(a=><tr key={a.id}><td>{a.jugadorNombre}</td><td>{a.opcion}</td><td>{formatearDinero(a.monto)}</td><td><EtiquetaEstado estado={a.estado}/></td><td>{a.estado==='pendiente'&&<button className="button secondary small" disabled={esperando} onClick={()=>setConfirmar({accion:'anularApuesta',id:a.id})}>Anular apuesta</button>}</td></tr>)}</tbody></table></div>}</section>
 <section className="panel"><h2>Cierre de ronda</h2>{mesa.registroDetallado ? <><p>{esRuleta?'Selecciona exactamente un número ganador (Pleno). El servidor determina las demás coincidencias.':'Selecciona las opciones ganadoras de esta ronda.'}</p><div className="searchrow" style={{marginBottom:15}}>{(esRuleta && plenos.length?plenos:opciones.filter(o=>o.activa)).map(o=><label key={o.id} style={{display:'flex',gap:7,alignItems:'center',margin:0,fontWeight:400}}><input style={{width:'auto',minHeight:0}} type={esRuleta?'radio':'checkbox'} name={esRuleta?'ganadora':undefined} checked={ganadoras.includes(o.id)} onChange={()=>toggleGanadora(o.id)}/>{o.nombre}</label>)}</div></>:<p>En póker, las apuestas se registran resueltas y el cierre no requiere indicar ganadores.</p>}
 <div className="row-actions"><button className="button" disabled={esperando||(mesa.registroDetallado&&ganadoras.length===0)} onClick={()=>setConfirmar({accion:'cerrar'})}>Cerrar ronda</button><button className="button danger" disabled={esperando} onClick={()=>setConfirmar({accion:'anularRonda'})}>Anular ronda</button></div></section></>}
 {confirmar&&<Confirmar titulo={confirmar.accion==='abrir'?'Abrir ronda':confirmar.accion==='cerrar'?'Cerrar ronda':confirmar.accion==='anularApuesta'?'Anular apuesta':'Anular ronda'} descripcion={confirmar.accion==='cerrar'?'El cierre liquida automáticamente las apuestas según el resultado. Revisa las opciones ganadoras antes de confirmar.':confirmar.accion==='anularRonda'?'La anulación devolverá los montos de las apuestas pendientes.':'¿Confirmas esta operación?'} esperando={esperando} onCerrar={()=>setConfirmar(null)} onConfirmar={ejecutar}/>}
 </div>;
}
