import type { Metadata } from 'next';
import { obtenerCamposSeguros } from '@/server/acciones/auth';
import { RegistroForm } from '@/components/auth/registro-form';
export const metadata:Metadata={title:'Registro de jugador'};
export default async function Registro(){const seguro=await obtenerCamposSeguros();return <main className="auth-layout"><div className="auth-visual" role="img" aria-label="Mesa de casino con fichas y emblema Casino"/><div className="auth-side"><RegistroForm seguro={seguro}/></div></main>}
