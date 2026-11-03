import { listarSuspensiones,listarInvestigaciones,obtenerUmbral } from '@/server/acciones/riesgo';
import { listarEmpleados } from '@/server/acciones/personal';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { RiesgoClient } from '@/components/admin/riesgo-client';
import { Alerta } from '@/components/comunes/estado';
export default async function Riesgo(){const [s,i,e,u,seguro]=await Promise.all([listarSuspensiones(false),listarInvestigaciones(true),listarEmpleados(),obtenerUmbral(),obtenerCamposSeguros()]);const err=[s,i,e,u].filter(x=>!x.ok).map(x=>x.ok?'':x.error.mensaje).join(' · ');if(err)return <Alerta mensaje={err}/>;if(!s.ok||!i.ok||!e.ok||!u.ok)return null;return <RiesgoClient suspensiones={s.datos} investigaciones={i.datos} empleados={e.datos} umbral={u.datos.umbralPerdidaDiaria} seguro={seguro}/>;}
