import { notFound } from 'next/navigation';
import { misMesasActuales, listarRondas } from '@/server/acciones/rondas';
import { listarOpciones, listarApuestas } from '@/server/acciones/apuestas';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { CrupierMesaClient } from '@/components/operacion/crupier-mesa';
import { Alerta } from '@/components/comunes/estado';
export default async function MesaCrupier({params}:{params:Promise<{mesaId:string}>}){
 const {mesaId}=await params;const id=Number(mesaId);if(!Number.isSafeInteger(id)||id<=0)notFound();
 const asignaciones=await misMesasActuales();if(!asignaciones.ok)return <Alerta mensaje={asignaciones.error.mensaje}/>;
 const asignacion=asignaciones.datos.find(x=>x.mesa.id===id);if(!asignacion)notFound();
 const [rondas,opciones,seguro]=await Promise.all([listarRondas(id),listarOpciones(asignacion.mesa.juegoId),obtenerCamposSeguros()]);
 if(!rondas.ok||!opciones.ok)return <Alerta mensaje={rondas.ok?opciones.ok?'Error de lectura':opciones.error.mensaje:rondas.error.mensaje}/>;
 const apuestas=asignacion.rondaAbierta?await listarApuestas(asignacion.rondaAbierta.id):{ok:true as const,datos:[]};
 if(!apuestas.ok)return <Alerta mensaje={apuestas.error.mensaje}/>;
 return <CrupierMesaClient asignacion={asignacion} rondas={rondas.datos} apuestas={apuestas.datos} opciones={opciones.datos} seguro={seguro}/>;
}
