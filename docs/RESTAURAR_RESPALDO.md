# Respaldo y restauración de la base (producción)

## Qué hay
El workflow `.github/workflows/respaldo.yml` hace cada día una copia del
esquema `public` de producción (pólizas, clientes, pagos, usuarios, catálogos,
casos...) y la guarda **cifrada** como artefacto de GitHub Actions durante
30 días: repositorio → Actions → "Respaldo diario de la base" → una ejecución
→ artefacto `respaldo-supabase`.

El repositorio es público: sin la frase `BACKUP_PASSPHRASE` el archivo es
ilegible. **Guarde esa frase también fuera de GitHub** (gestor de claves).

## Activarlo (una sola vez)
1. Supabase (proyecto de producción) → Connect → **Session pooler** → copie la
   cadena y reemplace `[YOUR-PASSWORD]` por la clave de la base.
2. GitHub → Settings → Secrets and variables → Actions → New repository secret:
   - `SUPABASE_DB_URL` = esa cadena
   - `BACKUP_PASSPHRASE` = una frase larga inventada por usted
3. Actions → "Respaldo diario de la base" → Run workflow, para probar. Debe
   terminar en verde y dejar un artefacto.

## Restaurar (probar SIEMPRE primero en el proyecto de pruebas)
Requiere PostgreSQL 17 (`pg_restore`) y `gpg`.

```bash
# 1. Descifrar (pide la frase)
gpg --output respaldo.dump --decrypt respaldo-AAAAMMDD-HHMM.dump.gpg

# 2. Ver qué contiene (sin tocar nada)
pg_restore --list respaldo.dump | head

# 3. Restaurar en una base VACÍA o de pruebas (cadena Session pooler del destino)
pg_restore --no-owner --no-privileges --clean --if-exists \
  --dbname "postgresql://postgres.xxxx:CLAVE@aws-0-....pooler.supabase.com:5432/postgres" \
  respaldo.dump
```

`--clean` borra y recrea los objetos del esquema `public` antes de cargarlos:
**no lo use contra producción sin estar seguro**. Para recuperar solo una
tabla: `pg_restore --data-only --table=polizas ...` hacia una base de pruebas y
copiar de ahí lo que falte.

## Qué NO incluye
- Usuarios de Supabase Auth (esta app usa su propia tabla `usuarios`, que sí
  está en `public`).
- Edge Functions y secretos (están en el repositorio / en el panel).
- Archivos: la app no guarda PDFs, solo procesa y descarta.

## Hacer una prueba de restauración
Un respaldo que nunca se restauró no es una garantía. Una vez al mes: descargue
el último, restáurelo en el proyecto de pruebas y compare el conteo de pólizas
(`select count(*) from polizas;`) con producción.
