import type { Resultado } from '@/lib/contrato';
export function avisoError<T>(resultado: Resultado<T>): string | null {
  return resultado.ok ? null : resultado.error.mensaje;
}
export function formatearDinero(valor: string) {
  const n = Number(valor);
  return Number.isFinite(n) ? new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', minimumFractionDigits:2,maximumFractionDigits:2 }).format(n) : valor;
}
export function formatearFecha(valor: string) {
  const d = new Date(valor);
  return Number.isNaN(d.getTime()) ? valor : new Intl.DateTimeFormat('es-CO', { dateStyle:'medium', timeStyle:'short', timeZone: 'America/Bogota' }).format(d);
}
export function Alerta({ mensaje, tipo = 'error' }: { mensaje: string | null; tipo?: 'error'|'success'|'info' }){
  if(!mensaje) return null;
  return <div className={'notice ' + (tipo === 'error' ? 'error' : tipo === 'success' ? 'success' : '')} role={tipo === 'error' ? 'alert' : 'status'}>{mensaje}</div>;
}
export function EstadoVacio({ mensaje }: { mensaje: string }){ return <div className="empty">{mensaje}</div>; }
export function EtiquetaEstado({ estado }: {estado:string}){
  const good = ['activo','activa','abierta','ganada','completada','cerrada'];
  const bad = ['inactivo','inactiva','anulada','perdida','suspendido','investigación'];
  const v = estado.toLowerCase();
  return <span className={'badge ' + (good.includes(v)?'good':bad.includes(v)?'bad':'warn')}>{estado}</span>;
}
