import assert from 'node:assert/strict';
import { crearMesa, actualizarMesa, desactivarMesa, crearAsignacion } from '../../src/server/mocks/mesas';
import { ErrorCasino } from '../../src/server/errores';
import { mockMesas, mockAsignaciones, mockApuestas, mockTurnos, mockRondas, mockEmpleados } from '../../src/server/mocks/datos';
const ctx = { sesion: null };
const s = { fechahora: 'test', firma: '0'.repeat(64) };
const f = (codigo: string, juegoId = 1, montoMinimo = '10.00', montoMaximo = '1000.00') => ({ codigo, juegoId, montoMinimo, montoMaximo });
const originales = [mockMesas,mockAsignaciones,mockApuestas,mockTurnos,mockRondas,mockEmpleados].map((a)=>structuredClone(a));
function reset() { [mockMesas,mockAsignaciones,mockApuestas,mockTurnos,mockRondas,mockEmpleados].forEach((a,i)=>a.splice(0,a.length,...structuredClone(originales[i]) as never[])); }
async function errorEsperado(codigo: string, fn: ()=>Promise<unknown>) {
 let fallo: unknown;
 try { await fn(); } catch(e) { fallo=e; }
 assert.ok(fallo instanceof ErrorCasino, 'Se esperaba ErrorCasino, se recibio '+String(fallo));
 assert.equal(fallo.codigo,codigo);
}
let aprobadas=0;
async function probar(nombre: string, run: ()=>Promise<void>) {
 reset(); await run(); aprobadas++; console.log('[OK]',nombre);
}
const turnoActual = () => mockTurnos.find(t=>Date.parse(t.fin)>Date.now())!;
const nuevaAsignacion = (turnoId:number,mesaId:number,crupierId=4,supervisorId=7) => crearAsignacion(ctx,{turnoId,mesaId,crupierId,supervisorId},s);
async function main() {
 await probar('Duplicado de codigo devuelve CA103',async()=>{ await errorEsperado('CA103',()=>crearMesa(ctx,f('R-01'),s)); });
 await probar('Minimo invalido devuelve CA103',async()=>{ await errorEsperado('CA103',()=>crearMesa(ctx,f('QA-MIN',1,'0.00'),s)); });
 await probar('Mesa inexistente al actualizar: CA104',async()=>{ await errorEsperado('CA104',()=>actualizarMesa(ctx,999,f('QA-MISSING'),s)); });
 await probar('Mesa inexistente al desactivar: CA104',async()=>{ await errorEsperado('CA104',()=>desactivarMesa(ctx,999,s)); });
 await probar('Crear mesa guarda juego y limites',async()=>{ const m=await crearMesa(ctx,f('QA-NUEVA'),s); assert.equal(m.juego,'Ruleta'); assert.equal(m.activa,true); });
 await probar('Cambiar juego sin relaciones esta permitido',async()=>{ const m=await crearMesa(ctx,f('QA-SIN'),s); const n=await actualizarMesa(ctx,m.id,f(m.codigo,2),s); assert.equal(n.juego,'Blackjack'); });
 await probar('Asignacion impide cambiar juego: CA124',async()=>{const m=await crearMesa(ctx,f('QA-ASIG'),s);await nuevaAsignacion(turnoActual().id,m.id);await errorEsperado('CA124',()=>actualizarMesa(ctx,m.id,f(m.codigo,2),s));assert.equal(mockMesas.find(x=>x.id===m.id)?.juegoId,1);});
 await probar('Rondas impiden cambiar el juego: CA124',async()=>{await errorEsperado('CA124',()=>actualizarMesa(ctx,1,f('R-01',2),s));});
 await probar('Renombrar actualiza proyecciones de asignaciones y apuestas',async()=>{await actualizarMesa(ctx,1,f('R-01-NUEVO',1),s);assert.ok(mockAsignaciones.filter(x=>x.mesaId===1).every(x=>x.mesaCodigo==='R-01-NUEVO'));assert.ok(mockApuestas.filter(x=>x.rondaNumero>=1&&x.mesaCodigo==='R-01-NUEVO').length>0);});
 await probar('Asignacion futura impide desactivar: CA125',async()=>{const m=await crearMesa(ctx,f('QA-FUT'),s);await nuevaAsignacion(turnoActual().id,m.id);await errorEsperado('CA125',()=>desactivarMesa(ctx,m.id,s));assert.equal(mockMesas.find(x=>x.id===m.id)?.activa,true);});
 await probar('Ronda abierta impide desactivar: CA125',async()=>{await errorEsperado('CA125',()=>desactivarMesa(ctx,1,s));});
 await probar('Asignacion historica permite desactivar',async()=>{const m=await crearMesa(ctx,f('QA-HIST',3),s);const t=mockTurnos.find(x=>Date.parse(x.fin)<Date.now())!;await nuevaAsignacion(t.id,m.id,5,7);await desactivarMesa(ctx,m.id,s);assert.equal(mockMesas.find(x=>x.id===m.id)?.activa,false);assert.ok(mockAsignaciones.some(x=>x.mesaId===m.id));});
 await probar('Mesa inactiva rechaza asignacion: CA112',async()=>{const m=await crearMesa(ctx,f('QA-INACT'),s);await desactivarMesa(ctx,m.id,s);await errorEsperado('CA112',()=>nuevaAsignacion(turnoActual().id,m.id));});
 await probar('Crupier sin competencia rechaza: CA115',async()=>{const m=await crearMesa(ctx,f('QA-COMP'),s);await errorEsperado('CA115',()=>nuevaAsignacion(turnoActual().id,m.id,5,7));});
 await probar('Mesa ya asignada en turno: CA116',async()=>{const m=await crearMesa(ctx,f('QA-DUP'),s);const t=turnoActual();await nuevaAsignacion(t.id,m.id);await errorEsperado('CA116',()=>nuevaAsignacion(t.id,m.id,3,7));});
 await probar('Crupier simultaneo en dos mesas: CA117',async()=>{const t=turnoActual();const m=await crearMesa(ctx,f('QA-CRUP'),s);await nuevaAsignacion(t.id,m.id);const m2=await crearMesa(ctx,f('QA-CRUP2'),s);await errorEsperado('CA117',()=>nuevaAsignacion(t.id,m2.id));});
 await probar('Rotacion por jornada: CA118',async()=>{const m=await crearMesa(ctx,f('QA-ROT',3),s);const t1=mockTurnos.find(x=>x.numero===1)!;const t3=mockTurnos.find(x=>x.numero===3)!;await nuevaAsignacion(t1.id,m.id,5,7);await errorEsperado('CA118',()=>nuevaAsignacion(t3.id,m.id,5,7));});
 await probar('Crupier invalido devuelve CA113',async()=>{const m=await crearMesa(ctx,f('QA-CRUPINV'),s);await errorEsperado('CA113',()=>nuevaAsignacion(turnoActual().id,m.id,1,7));});
 await probar('Supervisor invalido devuelve CA114',async()=>{const m=await crearMesa(ctx,f('QA-SUPINV'),s);await errorEsperado('CA114',()=>nuevaAsignacion(turnoActual().id,m.id,4,1));});
 reset();console.log('RESULTADO MOCK MESAS: OK='+aprobadas+' FALLO=0');
}
main().catch(e=>{reset();console.error('[FALLO]',e);process.exitCode=1;});
