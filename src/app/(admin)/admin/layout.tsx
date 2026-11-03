import { exigirSesion } from '@/server/auth/sesion';
import { BarraLateral } from '@/components/navegacion/barra-lateral';
export default async function AdminLayout({children}:Readonly<{children:React.ReactNode}>){
 const sesion=await exigirSesion('administrador');
 return <BarraLateral sesion={sesion}>{children}</BarraLateral>;
}
