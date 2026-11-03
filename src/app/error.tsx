'use client';
export default function ErrorUI({reset}:{error:Error & {digest?:string};reset:()=>void}){return <main style={{maxWidth:700,margin:'12vh auto',padding:30,textAlign:'center'}}><h1>No pudimos cargar esta sección</h1><p>Ocurrió un inconveniente al consultar el servidor. Puedes intentar de nuevo.</p><button className="button" onClick={reset}>Volver a intentar</button></main>}
