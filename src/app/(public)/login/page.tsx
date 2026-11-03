import type { Metadata } from 'next';
import { LoginForm } from '@/components/auth/login-form';
export const metadata:Metadata={title:'Iniciar sesión'};
export default function Login(){return <main className="auth-layout"><div className="auth-visual" role="img" aria-label="Mesa de casino con fichas y emblema Casino"/><div className="auth-side"><LoginForm/></div></main>}
