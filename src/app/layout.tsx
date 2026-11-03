import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: { default: 'Casino · Gestión del casino', template: '%s | Casino' },
  description: 'Sistema de gestión del casino — Pontificia Universidad Javeriana',
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="es"><body>{children}</body></html>;
}
