'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { emitirConcepto } from '@/server/acciones/mesas';
import type { Asignacion,CamposSeguros,Concepto } from '@/lib/contrato';
import { Alerta } from '@/components/comunes/estado';
const opciones:Concepto[]=['Genera ganancias','Genera pérdidas','Sospecha de fraude','Comportamiento neutro'];
export function SupervisorConceptos({asignacion,seguro}:{asignacion:Asignacion;seguro:CamposSeguros}){
 const router=useRouter();const [concepto,setConcepto]=useState<Concepto>('Comportamiento neutro');const [observacion,setObservacion]=useState('');const [cargando,setCargando]=useState(false);const [error,setError]=useState<string|null>(null);const [ok,setOk]=useState<string|null>(null);
 const [terminado,setTerminado]=useState(false);
 useEffect(() => {
   const revisar=()=>setTerminado(new Date(asignacion.fin).getTime()<=Date.now());
   const inicio=window.setTimeout(revisar,0);
   const intervalo=window.setInterval(revisar,10000);
   return ()=>{window.clearTimeout(inicio);window.clearInterval(intervalo);};
 },[asignacion.fin]);
 if(asignacion.concepto)return <p>Concepto emitido: <strong>{asignacion.concepto}</strong>{asignacion.observacion&&` · ${asignacion.observacion}`}</p>;
 // Control de conveniencia solamente: el servidor valida que el turno terminó.
 // Fecha de cierre evaluada desde un efecto, no durante render.
 async function enviar(e:React.FormEvent<HTMLFormElement>){e.preventDefault();if(cargando)return;setCargando(true);setError(null);try{const r=await emitirConcepto(asignacion.id,concepto,observacion.trim()||null,seguro);if(!r.ok){setError(r.error.mensaje);return;}setOk('Concepto registrado.');router.refresh();}catch{setError('No se pudo emitir el concepto.');}finally{setCargando(false);}}
 if(!terminado)return <p className="notice">El concepto estará disponible cuando termine el turno.</p>;
 return <form onSubmit={enviar}><div className="formgrid"><div><label htmlFor={`concepto-${asignacion.id}`}>Concepto sobre el crupier</label><select id={`concepto-${asignacion.id}`} value={concepto} onChange={e=>setConcepto(e.target.value as Concepto)}>{opciones.map(o=><option key={o} value={o}>{o}</option>)}</select></div><div><label htmlFor={`obs-${asignacion.id}`}>Observación (opcional)</label><input id={`obs-${asignacion.id}`} value={observacion} onChange={e=>setObservacion(e.target.value)}/></div></div><Alerta mensaje={error}/><Alerta mensaje={ok} tipo="success"/><button className="button" style={{marginTop:14}} disabled={cargando}>{cargando?'Guardando…':'Emitir concepto'}</button></form>;
}
