# ChronosITT – Sistema Web de Control de Asistencia mediante Código QR

Proyecto integrador de **Gestión de Proyectos de Software** (SC7C, Agosto-Diciembre 2026) – Instituto Tecnológico de Tijuana.

El docente genera un código QR por sesión de clase; el alumno lo escanea con su celular (misma red local), inicia sesión y su asistencia se registra con fecha y hora, sin duplicados.

## Equipo
| Integrante | Rol |
|---|---|
| Fabian Osvaldo Rodrigues Mendivil | Líder del proyecto / Backend / Frontend |
| Carlos Eliab Rodriguez Peraza | Backend / Frontend |
| Dafne Jael Moguel Benitez | Base de datos |
| Jorge Joshel Leon Cruz | QA / Documentación |

## Tecnologías
Frontend: HTML/CSS/JavaScript · Backend: Python (Flask) · Base de datos: SQL Server · Control de versiones: Git/GitHub

## Estructura del repositorio
```
docs/        Plan de calidad, artefactos y diagramas (casos de uso, flujo, ER)
database/    chronos_qr.sql (modelo de datos) y seed.sql (datos de ejemplo)
backend/     API en Python (app/)
frontend/    Interfaz web responsiva (index.html, css/, js/)
tests/       Pruebas (casos CP-01 a CP-06 del plan de calidad)
CHANGELOG.md Registro de cambios
```

## Cómo ejecutar el backend (desarrollo)
```bash
cd backend
pip install -r requirements.txt
python -m app.main        # http://localhost:5000/api/health (ejemplo)
```

## Flujo de trabajo en Git
- `main`: versión estable · `develop`: integración · `feature/<nombre>`: una rama por funcionalidad.
- Toda fusión por Pull Request revisado por otro integrante.
- Mensajes de commit: `tipo: descripción` (feat, fix, docs, test, chore).
- Defectos y cambios: GitHub Issues (etiquetas `bug`, `cambio`, severidad).
