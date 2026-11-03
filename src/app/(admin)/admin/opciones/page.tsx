import { listarJuegos } from '@/server/acciones/personal';
import { listarOpciones } from '@/server/acciones/apuestas';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { OpcionesClient } from '@/components/admin/opciones-client';
import { Alerta } from '@/components/comunes/estado';
import type { OpcionApuesta } from '@/lib/contrato';
export default async function Opciones(){const [j,seguro]=await Promise.all([listarJuegos(),obtenerCamposSeguros()]);if(!j.ok)return <Alerta mensaje={j.error.mensaje}/>;const registros=await Promise.all(j.datos.map(x=>listarOpciones(x.id)));const err=registros.find(x=>!x.ok);if(err&&!err.ok)return <Alerta mensaje={err.error.mensaje}/>;const mapa:Record<string,OpcionApuesta[]>={};for(let i=0;i<j.datos.length;i++){const r=registros[i];if(r.ok)mapa[j.datos[i].id]=r.datos;}return <OpcionesClient juegos={j.datos} opcionesPorJuego={mapa} seguro={seguro}/>;}
