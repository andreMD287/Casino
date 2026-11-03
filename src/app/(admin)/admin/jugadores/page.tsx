import { listarJugadores } from '@/server/acciones/riesgo';
import { Alerta } from '@/components/comunes/estado';
import { JugadoresClient } from '@/components/admin/jugadores-client';
export default async function Jugadores(){const r=await listarJugadores();if(!r.ok)return <Alerta mensaje={r.error.mensaje}/>;return <JugadoresClient jugadores={r.datos}/>;}
