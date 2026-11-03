'use client';
import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { derivarCredenciales } from '@/lib/srp-cliente';
import { crearEmpleado, actualizarEmpleado, desactivarEmpleado } from '@/server/acciones/personal';
import type { CamposSeguros, Empleado, Cargo } from '@/lib/contrato';
import { Alerta, EstadoVacio, EtiquetaEstado, formatearDinero } from '@/components/comunes/estado';
import { Confirmar } from '@/components/comunes/confirmar';

const blanco={nombre:'',documento:'',usuario:'',clave:'',cargo:'crupier' as Cargo,salarioMensual:''};
type Form=typeof blanco;
export function EmpleadosClient({empleados,seguro}: {empleados:Empleado[];seguro:CamposSeguros}){
 const router=useRouter();
 const [busqueda,setBusqueda]=useState('');const [filtro,setFiltro]=useState('todos');
 const [modo,setModo]=useState<'crear'|'editar'|null>(null);const [editar,setEditar]=useState<number|null>(null);
 const [form,setForm]=useState<Form>(blanco);const [cargando,setCargando]=useState(false);
 const [error,setError]=useState<string|null>(null);const [exito,setExito]=useState<string|null>(null);
 const [desactivar,setDesactivar]=useState<Empleado|null>(null);
 const visibles=empleados.filter(e=>(filtro==='todos'||(filtro==='activos'?e.activo:!e.activo))&&[e.nombre,e.usuario,e.documento].some(v=>v.toLowerCase().includes(busqueda.toLowerCase())));
 const editarCampo=<K extends keyof Form>(key:K,v:Form[K])=>setForm(p=>({...p,[key]:v}));
 const cerrar=()=>{if(!cargando){setModo(null);setEditar(null);setError(null);}};
 const abrirCrear=()=>{setForm(blanco);setEditar(null);setError(null);setExito(null);setModo('crear');};
 const abrirEditar=(e:Empleado)=>{setForm({nombre:e.nombre,documento:e.documento,usuario:e.usuario,clave:'',cargo:e.cargo,salarioMensual:e.salarioMensual});setEditar(e.id);setError(null);setExito(null);setModo('editar');};
 async function guardar(e:React.FormEvent<HTMLFormElement>){
  e.preventDefault();if(cargando)return;setError(null);setCargando(true);
  try{
   const datos={nombre:form.nombre.trim(),documento:form.documento.trim(),cargo:form.cargo,salarioMensual:form.salarioMensual};
   const r=modo==='crear'?await crearEmpleado(datos,await derivarCredenciales(form.usuario.trim(),form.clave),seguro):await actualizarEmpleado(editar!,datos,seguro);
   if(!r.ok){setError(r.error.codigo==='CA007'?'El formulario venció, recarga la página.':r.error.mensaje);return;}
   setExito(modo==='crear'?'Empleado registrado correctamente.':'Empleado actualizado correctamente.');setModo(null);router.refresh();
  }catch{setError('No se pudo guardar el empleado. Verifica la conexión.');}
  finally{setCargando(false);}
 }
 async function ejecutarDesactivacion(){
  if(!desactivar||cargando)return;setCargando(true);setError(null);
  try{const r=await desactivarEmpleado(desactivar.id,seguro);if(!r.ok){setError(r.error.codigo==='CA007'?'El formulario venció, recarga la página.':r.error.mensaje);return;}setExito('Empleado desactivado correctamente.');setDesactivar(null);router.refresh();}
  catch{setError('No se pudo desactivar el empleado.');}finally{setCargando(false);}
 }
 return <div className="stack">
  <div className="pagehead"><div><h1>Gestión de empleados</h1><p>Consulta, registra y administra el personal del casino</p></div><button type="button" className="button" onClick={abrirCrear}>＋ Registrar empleado</button></div>
  <Alerta mensaje={exito} tipo="success"/><Alerta mensaje={error}/>
  <section className="panel"><div className="searchrow"><div><label htmlFor="busqueda-empleado">Buscar empleado</label><input id="busqueda-empleado" type="search" placeholder="Nombre, usuario o documento…" value={busqueda} onChange={e=>setBusqueda(e.target.value)}/></div><div style={{flex:'0 1 200px'}}><label htmlFor="filtro-empleado">Estado</label><select id="filtro-empleado" value={filtro} onChange={e=>setFiltro(e.target.value)}><option value="todos">Todos</option><option value="activos">Activos</option><option value="inactivos">Inactivos</option></select></div></div></section>
  <section className="panel"><h2>Listado de empleados <span className="badge">{visibles.length}</span></h2>
   {visibles.length===0?<EstadoVacio mensaje="No encontramos empleados con esos filtros"/>:<div className="table-scroll"><table className="data-table"><thead><tr><th>Documento</th><th>Nombre</th><th>Usuario</th><th>Cargo</th><th>Salario</th><th>Estado</th><th>Acciones</th></tr></thead><tbody>
    {visibles.map(e=><tr key={e.id}><td>{e.documento}</td><td><strong>{e.nombre}</strong></td><td>{e.usuario}</td><td>{e.cargo}</td><td>{formatearDinero(e.salarioMensual)}</td><td><EtiquetaEstado estado={e.activo?'Activo':'Inactivo'}/></td><td><div className="row-actions"><Link className="button small secondary" href={`/admin/empleados/${e.id}`}>Competencias</Link><button className="button small secondary" onClick={()=>abrirEditar(e)}>Editar</button><button className="button small danger" disabled={!e.activo} onClick={()=>{setError(null);setDesactivar(e);}}>Desactivar</button></div></td></tr>)}
   </tbody></table></div>}</section>
  {modo&&<div className="modal-backdrop" role="presentation"><section className="modal" role="dialog" aria-modal="true" aria-labelledby="empleado-modal-title">
    <div className="modal-head"><h2 id="empleado-modal-title">{modo==='crear'?'Registrar empleado':'Editar empleado'}</h2><button className="button secondary small" type="button" onClick={cerrar} disabled={cargando} aria-label="Cerrar">✕</button></div>
    <form onSubmit={guardar}>
      <div className="formgrid"><div className="field"><label htmlFor="emp-nombre">Nombre completo</label><input id="emp-nombre" required value={form.nombre} onChange={e=>editarCampo('nombre',e.target.value)}/></div>
      <div className="field"><label htmlFor="emp-documento">Documento</label><input id="emp-documento" required value={form.documento} onChange={e=>editarCampo('documento',e.target.value)}/></div>
      {modo==='crear'&&<><div className="field"><label htmlFor="emp-usuario">Usuario</label><input id="emp-usuario" required pattern="[a-z0-9_.]{3,30}" value={form.usuario} onChange={e=>editarCampo('usuario',e.target.value)}/></div><div className="field"><label htmlFor="emp-clave">Contraseña inicial</label><input id="emp-clave" type="password" autoComplete="new-password" minLength={8} required value={form.clave} onChange={e=>editarCampo('clave',e.target.value)}/></div></>}
      <div className="field"><label htmlFor="emp-cargo">Cargo</label><select id="emp-cargo" value={form.cargo} onChange={e=>editarCampo('cargo',e.target.value as Cargo)}><option value="administrador">Administrador</option><option value="crupier">Crupier</option><option value="supervisor">Supervisor</option></select></div>
      <div className="field"><label htmlFor="emp-salario">Salario mensual</label><input id="emp-salario" type="text" inputMode="decimal" pattern="[0-9]+([.,][0-9]{1,2})?" title="Monto positivo con máximo dos decimales" required value={form.salarioMensual} onChange={e=>editarCampo('salarioMensual',e.target.value.replace(',','.'))}/></div></div>
      <Alerta mensaje={error}/>{error==='El formulario venció, recarga la página.'&&<button className="button secondary" type="button" onClick={()=>window.location.reload()}>Recargar</button>}
      <footer><button className="button secondary" type="button" onClick={cerrar} disabled={cargando}>Cancelar</button><button className="button" type="submit" disabled={cargando}>{cargando?'Guardando…':'Guardar empleado'}</button></footer>
    </form></section></div>}
  {desactivar&&<Confirmar titulo="Desactivar empleado" descripcion={`¿Confirmas la desactivación de ${desactivar.nombre}? El registro no se eliminará.`} confirmacion="Sí, desactivar" esperando={cargando} onCerrar={()=>setDesactivar(null)} onConfirmar={ejecutarDesactivacion}/>}
 </div>;
}
