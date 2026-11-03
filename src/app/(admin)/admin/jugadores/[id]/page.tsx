import { notFound } from 'next/navigation';
import { obtenerHistorial } from '@/server/acciones/riesgo';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { DetalleJugadorClient } from '@/components/admin/detalle-jugador-client';
import { Alerta } from '@/components/comunes/estado';
export default async function JugadorDetalle({params}:{params:Promise<{id:string}>}){
 const {id}=await params;const ident=Number(id);if(!Number.isSafeInteger(ident)||ident<=0)notFound();
 const [r,seguro]=await Promise.all([obtenerHistorial(ident),obtenerCamposSeguros()]);
 if(!r.ok)return <Alerta mensaje={r.error.mensaje}/>;
 return <DetalleJugadorClient historial={r.datos} seguro={seguro}/>;
}
