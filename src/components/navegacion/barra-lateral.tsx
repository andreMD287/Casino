'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useState } from 'react';
import { cerrarSesion } from '@/server/acciones/auth';
import { menus } from './menu';
import type { Sesion } from '@/lib/contrato';

export function BarraLateral({ sesion, children }: { sesion: Sesion; children: React.ReactNode }) {
  const path = usePathname();
  const router = useRouter();
  const [cerrando, setCerrando] = useState(false);
  async function salir(){
    if(cerrando) return;
    setCerrando(true);
    try { await cerrarSesion(); router.replace('/login'); router.refresh(); }
    catch { setCerrando(false); }
  }
  return <div className="shell">
    <aside className="sidebar" aria-label="Navegación del casino">
      <Link href={`/${sesion.rol === 'administrador' ? 'admin' : sesion.rol}`} className="brand">Casino</Link>
      <div className="brand-sub">SISTEMA DE GESTIÓN<br/>DEL CASINO</div>
      <nav className="nav" aria-label="Menú de mi rol">
        {menus[sesion.rol].map(item => <Link key={item.href} href={item.href}
          aria-current={path === item.href || (item.href !== '/admin' && path.startsWith(item.href + '/')) ? 'page' : undefined}
          className={path === item.href || (item.href !== '/admin' && path.startsWith(item.href + '/')) ? 'active' : ''}>
          <span className="nav-icon" aria-hidden="true">{item.icono}</span>{item.titulo}</Link>)}
      </nav>
      <div className="sidefoot">Diseño Casino · Opción 6<br/>Gestión segura por roles</div>
    </aside>
    <div className="main">
      <header className="topbar"><div><strong>Casino · {sesion.rol}</strong><div className="description">Sistema de gestión del casino</div></div>
        <div className="top-user"><div className="avatar" aria-hidden="true">{sesion.nombre.slice(0,1).toUpperCase()}</div><div><strong>{sesion.nombre}</strong><div className="description">{sesion.rol}</div></div><button className="signout" disabled={cerrando} onClick={salir}>{cerrando ? 'Saliendo…' : 'Cerrar sesión'}</button></div>
      </header>
      <main id="contenido" className="content">{children}</main>
    </div>
  </div>;
}
