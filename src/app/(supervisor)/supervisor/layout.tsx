import { exigirSesion } from '@/server/auth/sesion';
import { BarraLateral } from '@/components/navegacion/barra-lateral';
export default async function SupervisorLayout({children}:{children:React.ReactNode}){const sesion=await exigirSesion('supervisor');return <BarraLateral sesion={sesion}>{children}</BarraLateral>}
