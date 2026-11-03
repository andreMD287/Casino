'use client';
import { useEffect } from 'react';
export function Confirmar({ titulo, descripcion, confirmacion, esperando, onCerrar, onConfirmar }: {
  titulo: string; descripcion: string; confirmacion?:string; esperando:boolean; onCerrar:()=>void; onConfirmar:()=>void;
}) {
  useEffect(()=>{function alTeclado(e:KeyboardEvent){ if(e.key==='Escape'&&!esperando)onCerrar(); } window.addEventListener('keydown',alTeclado);return()=>window.removeEventListener('keydown',alTeclado);},[onCerrar,esperando]);
  return <div className="modal-backdrop" role="presentation"><section className="modal" role="alertdialog" aria-modal="true" aria-labelledby="confirm-titulo" aria-describedby="confirm-texto">
    <div className="modal-head"><h2 id="confirm-titulo">{titulo}</h2><button className="button secondary small" type="button" disabled={esperando} onClick={onCerrar} aria-label="Cerrar diálogo">✕</button></div>
    <p id="confirm-texto">{descripcion}</p>
    <footer><button type="button" className="button secondary" disabled={esperando} onClick={onCerrar}>Cancelar</button><button type="button" className="button" disabled={esperando} onClick={onConfirmar}>{esperando?'Procesando…':(confirmacion??'Confirmar')}</button></footer>
  </section></div>;
}
