import { redirect } from 'next/navigation';
import { obtenerSesion } from '@/server/auth/sesion';
export default async function Inicio() {
  const sesion = await obtenerSesion();
  if (!sesion) redirect('/login');
  redirect(sesion.rol === 'administrador' ? '/admin' : `/${sesion.rol}`);
}
