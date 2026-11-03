import { listarJornadas,listarTurnos,listarAsignaciones,listarMesas } from '@/server/acciones/mesas';
import { listarEmpleados } from '@/server/acciones/personal';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { TurnosClient } from '@/components/admin/turnos-client';
import { Alerta } from '@/components/comunes/estado';
export default async function Turnos({searchParams}:{searchParams:Promise<{jornada?:string}>}){
 const {jornada}=await searchParams;const [jornadas,mesas,empleados,seguro]=await Promise.all([listarJornadas(),listarMesas(),listarEmpleados(),obtenerCamposSeguros()]);
 if(!jornadas.ok||!mesas.ok||!empleados.ok)return <Alerta mensaje={jornadas.ok?mesas.ok?empleados.ok?'Error':empleados.error.mensaje:mesas.error.mensaje:jornadas.error.mensaje}/>;
 const seleccionada=jornadas.datos.find(j=>j.id===Number(jornada))??jornadas.datos[0]??null;
 const [turnos,asignaciones]=seleccionada?await Promise.all([listarTurnos(seleccionada.id),listarAsignaciones(seleccionada.id)]):[{ok:true as const,datos:[]},{ok:true as const,datos:[]}];
 if(!turnos.ok||!asignaciones.ok)return <Alerta mensaje={turnos.ok?asignaciones.ok?'Error':asignaciones.error.mensaje:turnos.error.mensaje}/>;
 return <TurnosClient jornadas={jornadas.datos} seleccionada={seleccionada} turnos={turnos.datos} asignaciones={asignaciones.datos} mesas={mesas.datos} empleados={empleados.datos} seguro={seguro}/>;
}
