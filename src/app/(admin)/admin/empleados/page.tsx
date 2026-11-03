import { listarEmpleados } from '@/server/acciones/personal';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { EmpleadosClient } from '@/components/admin/empleados-client';
import { Alerta } from '@/components/comunes/estado';
export default async function EmpleadosPage(){
 const [lista,seguro]=await Promise.all([listarEmpleados(),obtenerCamposSeguros()]);
 if(!lista.ok)return <><h1>Gestión de empleados</h1><Alerta mensaje={lista.error.mensaje}/></>;
 return <EmpleadosClient empleados={lista.datos} seguro={seguro}/>;
}
