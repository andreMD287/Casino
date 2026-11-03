'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { derivarCredenciales } from '@/lib/srp-cliente';
import { registrarJugador } from '@/server/acciones/auth';
import { Alerta } from '@/components/comunes/estado';
import type { CamposSeguros } from '@/lib/contrato';

export function RegistroForm({seguro}: {seguro:CamposSeguros}){
  const router=useRouter();
  const [documento,setDocumento]=useState('');const [nombre,setNombre]=useState('');const [fechaNacimiento,setFechaNacimiento]=useState('');
  const [usuario,setUsuario]=useState('');const [clave,setClave]=useState('');const [confirmar,setConfirmar]=useState('');
  const [mostrar,setMostrar]=useState(false);const [cargando,setCargando]=useState(false);const [error,setError]=useState<string|null>(null);
  const [codigo,setCodigo]=useState<string|null>(null);
  async function registrar(e:React.FormEvent<HTMLFormElement>){
    e.preventDefault(); if(cargando) return;
    if(clave!==confirmar){setError('Las contraseñas no coinciden.');return;}
    setCargando(true);setError(null);
    try{
      // La contraseña solo se usa para derivar el verificador SRP en el navegador.
      const cred=await derivarCredenciales(usuario.trim(),clave);
      const r=await registrarJugador({documento:documento.trim(),nombre:nombre.trim(),fechaNacimiento},cred,seguro);
      if(!r.ok){setError(r.error.codigo==='CA007'?'El formulario venció, recarga la página.':r.error.mensaje);return;}
      setCodigo(r.datos.codigo);setClave('');setConfirmar('');router.refresh();
    }catch{setError('No fue posible completar el registro. Inténtalo de nuevo.');}
    finally{setCargando(false);}
  }
  if(codigo)return <div className="auth-card auth-success"><h1>¡Registro completado!</h1><p>Tu cuenta de jugador ya fue creada.</p><div className="panel"><p className="muted">Tu código de cliente</p><h2>{codigo}</h2><p>Conserva este código para identificarte al realizar apuestas a través del crupier.</p></div><Link className="button block" href="/login">Ir a iniciar sesión</Link></div>;
  return <form className="auth-card" onSubmit={registrar}>
    <h1>Registro de jugador</h1><p className="subtitle">Crea tu cuenta para empezar a jugar</p><div className="ornament" aria-hidden="true">── ✦ ──</div>
    <div className="formgrid">
      <div className="field"><label htmlFor="documento">Documento *</label><input id="documento" value={documento} onChange={e=>setDocumento(e.target.value)} placeholder="Número de documento" required /></div>
      <div className="field"><label htmlFor="nombre">Nombre completo *</label><input id="nombre" value={nombre} onChange={e=>setNombre(e.target.value)} placeholder="Nombres y apellidos" required /></div>
      <div className="field"><label htmlFor="fecha">Fecha de nacimiento *</label><input id="fecha" type="date" max={new Date().toLocaleDateString('en-CA',{timeZone:'America/Bogota'})} value={fechaNacimiento} onChange={e=>setFechaNacimiento(e.target.value)} required /></div>
      <div className="field"><label htmlFor="usuario">Usuario *</label><input id="usuario" value={usuario} onChange={e=>setUsuario(e.target.value)} pattern="[a-z0-9_.]{3,30}" title="Entre 3 y 30 caracteres: letras minúsculas, números, guion bajo o punto" autoComplete="username" required /></div>
      <div className="field"><label htmlFor="clave">Contraseña *</label><input id="clave" type={mostrar?'text':'password'} value={clave} onChange={e=>setClave(e.target.value)} autoComplete="new-password" minLength={8} required /></div>
      <div className="field"><label htmlFor="confirmar">Confirmar contraseña *</label><input id="confirmar" type={mostrar?'text':'password'} value={confirmar} onChange={e=>setConfirmar(e.target.value)} autoComplete="new-password" required /></div>
    </div>
    <label style={{fontWeight:400,marginBottom:16}}><input type="checkbox" style={{width:'auto',minHeight:0,marginRight:8}} checked={mostrar} onChange={e=>setMostrar(e.target.checked)}/>Mostrar contraseñas</label>
    <Alerta mensaje={error}/>{error==='El formulario venció, recarga la página.'&&<button className="button secondary" type="button" onClick={()=>window.location.reload()}>Recargar formulario</button>}
    <button className="button block" type="submit" disabled={cargando}>{cargando?'Registrando…':'Registrarme'}</button>
    <p className="auth-foot">¿Ya tienes cuenta? <Link className="textlink" href="/login">Inicia sesión</Link></p>
  </form>
}
