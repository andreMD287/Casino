import { listarMesas } from '@/server/acciones/mesas';
import { listarJuegos } from '@/server/acciones/personal';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { MesasClient } from '@/components/admin/mesas-client';
import { Alerta } from '@/components/comunes/estado';
export default async function Mesas(){const [mesas,juegos,seguro]=await Promise.all([listarMesas(),listarJuegos(),obtenerCamposSeguros()]);if(!mesas.ok||!juegos.ok)return <Alerta mensaje={mesas.ok?juegos.ok?'Error':juegos.error.mensaje:mesas.error.mensaje}/>;return <MesasClient mesas={mesas.datos} juegos={juegos.datos} seguro={seguro}/>;}
