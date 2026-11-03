'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { solicitarPausa } from '@/server/acciones/riesgo';
import type { CamposSeguros } from '@/lib/contrato';
import { Alerta } from '@/components/comunes/estado';
import { Confirmar } from '@/components/comunes/confirmar';
export function JugadorPausa({seguro,habilitado}:{seguro:CamposSeguros;habilitado:boolean}){
 const [confirma,setConfirma]=useState(false);const [ocupado,setOcupado]=useState(false);const [mensaje,setMensaje]=useState<string|null>(null);const [error,setError]=useState<string|null>(null);const router=useRouter();
 async function ejecutar(){if(ocupado)return;setOcupado(true);setError(null);try{const r=await solicitarPausa(seguro);if(!r.ok){setError(r.error.mensaje);setConfirma(false);return;}setMensaje('Tu pausa voluntaria de 24 horas fue registrada. No podrás apostar mientras esté vigente.');setConfirma(false);router.refresh();}catch{setError('No se pudo registrar la pausa.');setConfirma(false);}finally{setOcupado(false);}}
 return <div className="panel"><h2>Pausa voluntaria</h2><p>Puedes solicitar una suspensión temporal de 24 horas. Durante la pausa no podrás apostar.</p><Alerta mensaje={mensaje} tipo="success"/><Alerta mensaje={error}/><button className="button" disabled={!habilitado||ocupado} onClick={()=>setConfirma(true)}>Solicitar pausa de 24 horas</button>{confirma&&<Confirmar titulo="Solicitar pausa de 24 horas" descripcion="¿Confirmas la pausa? Tu cuenta quedará suspendida temporalmente durante 24 horas y no podrás hacer apuestas en ese período." confirmacion="Confirmar pausa" esperando={ocupado} onCerrar={()=>setConfirma(false)} onConfirmar={ejecutar}/>}</div>;
}
