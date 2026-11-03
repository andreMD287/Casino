import { exigirSesion } from '@/server/auth/sesion';
import { BarraLateral } from '@/components/navegacion/barra-lateral';
export default async function JugadorLayout({children}:{children:React.ReactNode}){const sesion=await exigirSesion('jugador');return <BarraLateral sesion={sesion}>{children}</BarraLateral>}
