import assert from 'node:assert/strict';
import { eliminarAsignacion, eliminarTurno } from '../../src/server/mocks/mesas';
import { mockAsignaciones, mockTurnos, mockRondas } from '../../src/server/mocks/datos';
import { ErrorCasino } from '../../src/server/errores';
const ctx={sesion:null};
const seguro={fechahora:'test',firma:'0'.repeat(64)};
const respaldos=[mockAsignaciones,mockTurnos,mockRondas].map(a=>structuredClone(a));
const restaurar=()=>[mockAsignaciones,mockTurnos,mockRondas].forEach((a,i)=>a.splice(0,a.length,...structuredClone(respaldos[i]) as never[]));
async function rechaza(codigo:string, accion:()=>Promise<unknown>){
 let err:unknown;
 try {await accion();} catch(e){err=e;}
 assert.ok(err instanceof ErrorCasino,'Se esperaba ErrorCasino');
 assert.equal(err.codigo,codigo);
}
let ok=0;
function marcar(etiqueta:string){ok++;console.log('[OK]',etiqueta);}
async function main(){
 const baseA=mockAsignaciones[0], baseT=mockTurnos[0];
 assert.ok(baseA && baseT,'No hay datos mock base');
 const idT=999001,idA=999002;
 const t={...baseT,id:idT,numero:999};
 const a={...baseA,id:idA,turnoId:idT,turnoNumero:t.numero,concepto:'Comportamiento neutro' as const,observacion:'Concepto de prueba'};
 mockTurnos.push(t);mockAsignaciones.push(a);
 await rechaza('CA126',()=>eliminarAsignacion(ctx,idA,seguro));
 marcar('Asignacion con concepto bloqueada CA126');
 assert.ok(mockAsignaciones.some(x=>x.id===idA));marcar('Asignacion y concepto conservados');
 await rechaza('CA126',()=>eliminarTurno(ctx,idT,seguro));
 marcar('Turno con concepto bloqueado CA126');
 assert.ok(mockTurnos.some(x=>x.id===idT)&&mockAsignaciones.some(x=>x.id===idA));
 marcar('Turno y concepto conservados');
 a.concepto=null as never;
 await eliminarAsignacion(ctx,idA,seguro);
 assert.ok(!mockAsignaciones.some(x=>x.id===idA));marcar('Asignacion sin historial eliminada');
 await eliminarTurno(ctx,idT,seguro);
 assert.ok(!mockTurnos.some(x=>x.id===idT));marcar('Turno vacio eliminado');
 await rechaza('CA106',()=>eliminarAsignacion(ctx,idA,seguro));marcar('Asignacion inexistente CA106');
 await rechaza('CA105',()=>eliminarTurno(ctx,idT,seguro));marcar('Turno inexistente CA105');
 console.log(`RESULTADO MOCK CONCEPTOS: OK=${ok} FALLO=0`);
}
main().catch(e=>{console.error('[FALLO]',e);process.exitCode=1;}).finally(restaurar);
