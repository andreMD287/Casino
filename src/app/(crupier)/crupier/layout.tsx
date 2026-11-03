import { exigirSesion } from '@/server/auth/sesion';
import { BarraLateral } from '@/components/navegacion/barra-lateral';
export default async function CrupierLayout({children}:{children:React.ReactNode}){const sesion=await exigirSesion('crupier');return <BarraLateral sesion={sesion}>{children}</BarraLateral>}
