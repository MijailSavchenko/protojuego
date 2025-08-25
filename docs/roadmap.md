\# Roadmap — Protojuego



\## Fase 1 — Núcleo estable

\- Core estable (luciérnagas, fondo negro, sin huevos “pegados”).

\- Ritual: fusión de bits y aparición del huevo.

\- Huevo: arrastre, animación por fases, crack → hatch.

\- Debug: menú F1 con acciones de test.



\## Fase 2 — Tipos y balance básico

\- Tabla de tipos (TypesDB) integrada (XENO primero, resto después).

\- Afinidades/conflictos básicos visibles en UI de debug.



\## Fase 3 — Criatura inicial (Xeno)

\- Sprite base + estados de idle y reacción a input.

\- Stats iniciales + crecimiento simple.



\## Fase 4 — Sistemas de juego

\- Comida, higiene, sueño (boucles cortos tipo tamagotchi).

\- Eventos aleatorios suaves.



\## Fase 5 — Pulido y VFX

\- Partículas y flashes afinados.

\- Sonidos mínimos (tap, hatch, ritual).



---



\## Milestones

\- \*\*M1 — Core \& Ritual\*\*: base estable, ritual y huevo funcional (arrastre + hatch).

\- \*\*M2 — Xeno\*\*: primera criatura jugable.

\- \*\*M3 — Bucles\*\*: comida/higiene/sueño básicos.

\- \*\*M4 — Pulido\*\*: vfx/sfx + rendimiento.



\## Reglas de trabajo

\- Ramas por feature (`feature/...`), PRs pequeñas, review antes de merge.

\- No tocar bloques “cerrados”; si algo falla, revert y fix aislado.

\- Todo cambio visual con opción de debug para probarlo rápido.



