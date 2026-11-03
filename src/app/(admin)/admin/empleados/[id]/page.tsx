import { notFound } from 'next/navigation';
import { listarEmpleados, listarJuegos } from '@/server/acciones/personal';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { CompetenciasClient } from '@/components/admin/competencias-client';
import { Alerta } from '@/components/comunes/estado';
export default async function EmpleadoDetalle({params}:{params:Promise<{id:string}>}){
 const {id}=await params;const ident=Number(id);if(!Number.isSafeInteger(ident)||ident<=0)notFound();
 const [empleados,juegos,seguro]=await Promise.all([listarEmpleados(),listarJuegos(),obtenerCamposSeguros()]);
 if(!empleados.ok||!juegos.ok)return <Alerta mensaje={empleados.ok?juegos.ok?'Error de lectura':juegos.error.mensaje:empleados.error.mensaje}/>;
 const e=empleados.datos.find(x=>x.id===ident);if(!e)notFound();
 return <CompetenciasClient empleado={e} juegos={juegos.datos} seguro={seguro}/>;
}
