import Link from 'next/link';
export default function Prohibido(){return <main style={{maxWidth:660,margin:'13vh auto',padding:25,textAlign:'center'}}><h1>Acceso no autorizado</h1><p>Tu cuenta no tiene permiso para ingresar a esta sección. Puedes volver a tu panel principal.</p><Link href="/" className="button">Ir a mi inicio</Link></main>}
