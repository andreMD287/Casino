// Proxy (antes "middleware"; Next 16 lo renombró a proxy.ts).
// Solo mira si EXISTE la cookie de sesión: no consulta la BD. La verificación real
// la hacen exigirSesion (layouts) y crearAccion (acciones).
import { NextResponse, type NextRequest } from 'next/server';

const COOKIE_SESION = 'casino_sesion';
const COOKIE_CANAL = 'casino_canal';
const RUTAS_PUBLICAS = new Set(['/', '/login', '/registro', '/prohibido']);

function canalAleatorio(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function proxy(request: NextRequest) {
  const { pathname, search } = request.nextUrl;

  if (!RUTAS_PUBLICAS.has(pathname) && !request.cookies.has(COOKIE_SESION)) {
    const url = new URL('/login', request.url);
    url.searchParams.set('siguiente', pathname + search);
    return NextResponse.redirect(url);
  }

  // Canal anónimo para firmar formularios sin sesión (por ejemplo, el registro de jugadores).
  // Se agrega a la petición actual y a la respuesta, para que la página ya lo vea en la primera visita.
  if (!request.cookies.has(COOKIE_CANAL)) {
    const canal = canalAleatorio();
    request.cookies.set(COOKIE_CANAL, canal);
    const respuesta = NextResponse.next({ request: { headers: request.headers } });
    respuesta.cookies.set({
      name: COOKIE_CANAL,
      value: canal,
      httpOnly: true,
      sameSite: 'strict',
      secure: process.env.NODE_ENV === 'production',
      path: '/',
    });
    return respuesta;
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|css|js|map)$).*)'],
};
