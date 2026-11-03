import Link from 'next/link';
export default function NoEncontrado(){return <main style={{maxWidth:660,margin:'13vh auto',padding:25,textAlign:'center'}}><h1>Esta página no existe</h1><p>Comprueba la dirección o regresa al inicio.</p><Link href="/" className="button">Volver al inicio</Link></main>}
