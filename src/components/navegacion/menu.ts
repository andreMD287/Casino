import type { Rol } from '@/lib/contrato';
export type MenuItem = { titulo: string; href: string; icono: string };
export const menus: Record<Rol, MenuItem[]> = {
  administrador: [
    { titulo: 'Panel principal', href: '/admin', icono: '⌂' },
    { titulo: 'Empleados', href: '/admin/empleados', icono: '♙' },
    { titulo: 'Mesas', href: '/admin/mesas', icono: '♣' },
    { titulo: 'Turnos y asignaciones', href: '/admin/turnos', icono: '▦' },
    { titulo: 'Opciones de apuesta', href: '/admin/opciones', icono: '♠' },
    { titulo: 'Jugadores', href: '/admin/jugadores', icono: '♙' },
    { titulo: 'Riesgo', href: '/admin/riesgo', icono: '♢' },
    { titulo: 'Reportes', href: '/admin/reportes', icono: '▥' },
  ],
  crupier: [{titulo:'Mis mesas',href:'/crupier',icono:'♣'}],
  supervisor: [{titulo:'Mis asignaciones',href:'/supervisor',icono:'▦'}],
  jugador: [{titulo:'Mi cuenta',href:'/jugador',icono:'♙'}],
};
