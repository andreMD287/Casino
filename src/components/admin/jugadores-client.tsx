'use client';
import Link from 'next/link';
import { useState } from 'react';
import type { Jugador } from '@/lib/contrato';
import { EtiquetaEstado, EstadoVacio, formatearDinero } from '@/components/comunes/estado';
export function JugadoresClient({jugadores}:{jugadores:Jugador[]}){
 const [filtro,setFiltro]=useState('');
 const visibles=jugadores.filter(j=>[j.codigo,j.nombre,j.documento,j.estado].some(v=>v.toLowerCase().includes(filtro.toLowerCase())));
 return <div className="stack"><div className="pagehead"><div><h1>Gestión de jugadores</h1><p>Consulta cuentas, saldos y el historial de cada cliente</p></div></div>
 <section className="panel"><label htmlFor="buscar-jugador">Buscar jugador</label><input id="buscar-jugador" type="search" value={filtro} onChange={e=>setFiltro(e.target.value)} placeholder="Código, nombre, documento o estado…"/></section>
 <section className="panel"><h2>Jugadores registrados <span className="badge">{visibles.length}</span></h2>{visibles.length===0?<EstadoVacio mensaje="No hay jugadores con esa búsqueda"/>:<div className="table-scroll"><table className="data-table"><thead><tr><th>Código</th><th>Nombre</th><th>Documento</th><th>Saldo</th><th>Estado</th><th>Acciones</th></tr></thead><tbody>{visibles.map(j=><tr key={j.id}><td><strong>{j.codigo}</strong></td><td>{j.nombre}</td><td>{j.documento}</td><td>{formatearDinero(j.saldo)}</td><td><EtiquetaEstado estado={j.estado}/></td><td><Link className="button small secondary" href={`/admin/jugadores/${j.id}`}>Ver historial y consignar</Link></td></tr>)}</tbody></table></div>}</section></div>;
}
