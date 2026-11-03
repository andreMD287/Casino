# Dificultades y decisiones — Frontend

1. La rama `andres/backend` y el repositorio completo no pudieron descargarse al entorno de preparación. Se desarrollaron componentes contra las firmas del contrato compartido y se mantuvieron fuera del repositorio original para evitar sobrescribir trabajo de otros miembros.
2. La consignación administrativa se dejó conectada a su firma declarada, pero la implementación de Andrés todavía estaba pendiente de publicación y pruebas al momento de crear el paquete. El formulario informa el resultado de la Server Action y no altera localmente el saldo.
3. Se priorizó replicar una identidad visual consistente, extraer componentes reutilizables y cubrir las rutas funcionales del contrato. La integración real y las evidencias requieren un entorno con la rama del backend y PostgreSQL.
4. Se validó la sintaxis de los archivos TypeScript, pero todavía no se ha ejecutado `next build` ni ESLint contra el repositorio completo. No se presenta esa validación como realizada.
