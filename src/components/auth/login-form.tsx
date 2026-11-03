'use client';
import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { iniciarSesion } from '@/lib/srp-cliente';
import { Alerta } from '@/components/comunes/estado';

export function LoginForm(){
  const router=useRouter();
  const [usuario,setUsuario]=useState('');
  const [clave,setClave]=useState('');
  const [mostrar,setMostrar]=useState(false);
  const [procesando,setProcesando]=useState(false);
  const [error,setError]=useState<string|null>(null);
  async function entrar(e:React.FormEvent<HTMLFormElement>){
    e.preventDefault(); if(procesando) return;
    setProcesando(true); setError(null);
    try {
      const respuesta=await iniciarSesion(usuario.trim(),clave);
      if(!respuesta.ok){setError(respuesta.error.mensaje || 'No fue posible iniciar sesión'); return;}
      const ruta = respuesta.datos.rol==='administrador' ? '/admin' : `/${respuesta.datos.rol}`;
      router.replace(ruta);router.refresh();
    } catch {setError('No fue posible conectar con el servidor. Intenta nuevamente.');}
    finally {setProcesando(false);}
  }
  return <form className="auth-card" onSubmit={entrar} autoComplete="on">
    <h1>Iniciar sesión</h1><p className="subtitle">Accede al sistema de gestión del casino</p><div className="ornament" aria-hidden="true">── ✦ ──</div>
    <div className="field"><label htmlFor="login-usuario">Usuario</label><input id="login-usuario" value={usuario} onChange={e=>setUsuario(e.target.value)} minLength={3} maxLength={30} autoComplete="username" placeholder="Ingresa tu usuario" required /></div>
    <div className="field"><label htmlFor="login-clave">Contraseña</label><div style={{display:'flex',gap:7}}><input id="login-clave" type={mostrar?'text':'password'} value={clave} onChange={e=>setClave(e.target.value)} autoComplete="current-password" placeholder="Ingresa tu contraseña" required /><button className="button secondary small" type="button" onClick={()=>setMostrar(v=>!v)} aria-label={mostrar?'Ocultar contraseña':'Mostrar contraseña'}>{mostrar?'Ocultar':'Mostrar'}</button></div></div>
    <Alerta mensaje={error}/>
    <button type="submit" className="button block" disabled={procesando}>{procesando?'Verificando…':'Ingresar'}</button>
    <p className="auth-foot">¿No tienes cuenta? <Link className="textlink" href="/registro">Regístrate</Link></p>
  </form>
}
