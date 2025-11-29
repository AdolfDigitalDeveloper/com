#!/usr/bin/env bash
set -euo pipefail

# create_dom_utils_patch_zip.sh (versión final)
# Crea dom-utils-consolidation-patch.zip con:
#  - package.json
#  - rollup.config.js
#  - src/ (contenido consolidado)
#  - legacy/ (archivos legacy con formato legacy/<ruta>.old.js)
#  - README-DOM-UTILS-PATCH.md
#  - CHANGELOG.txt
#  - apply_dom_utils_patch.sh (si existe)
#
# Uso:
#   chmod +x create_dom_utils_patch_zip.sh
#   ./create_dom_utils_patch_zip.sh
#
# Resultado: dom-utils-consolidation-patch.zip en el directorio actual.

OUT_ZIP="dom-utils-consolidation-patch.zip"
TMPDIR="$(mktemp -d)"
CWD="$(pwd)"
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

echo "Creando staging temporal en: $TMPDIR"

# Lista de legacy esperados y posibles fuentes donde encontrarlos
declare -A LEGACY_MAP=(
  ["legacy/src/index.old.js"]="src/index.js src/index.js.old legacy/src.index.old.js legacy/src.index.old.js"
  ["legacy/src/core/dom-extensions.old.js"]="src/core/dom-extensions.js legacy/src/core/dom-extensions.old.js legacy/src/core/dom-extensions.js.old"
  ["legacy/src/ajax/fetch.old.js"]="src/ajax/fetch.js legacy/src/ajax/fetch.old.js legacy/src/ajax/fetch.js.old"
  ["legacy/rollup.config.old.js"]="rollup.config.js legacy/rollup.config.old.js legacy/rollup.config.js.old"
  ["legacy/src/core/bottom-sheet-base.old.js"]="src/core/bottom-sheet-base.js legacy/src/core/bottom-sheet-base.old.js legacy/src/core/bottom-sheet-base.js.old"
  ["legacy/src/core/bottom-sheet.old.js"]="src/core/bottom-sheet.js legacy/src/core/bottom-sheet.old.js legacy/src/core/bottom-sheet.js.old"
)

# Asegura que exista la carpeta legacy en el TMP (para incluir en zip aunque venga vacía)
mkdir -p "$TMPDIR/legacy/src/core" "$TMPDIR/src" || true

# Para cada archivo legacy esperado: intenta localizar una fuente común y copiarla a TMP con nombre estandarizado.
for target in "${!LEGACY_MAP[@]}"; do
  found=""
  for candidate in ${LEGACY_MAP[$target]}; do
    if [ -f "$CWD/$candidate" ]; then
      found="$CWD/$candidate"
      break
    fi
  done

  dest="$TMPDIR/$target"
  destdir="$(dirname "$dest")"
  mkdir -p "$destdir"

  if [ -n "$found" ]; then
    echo "Incluyendo legacy desde: $found -> $target"
    cp -p "$found" "$dest"
  else
    # No se encontró fuente: crear stub informativo para no romper el zip y avisar al usuario.
    echo "No se encontró fuente para $target. Creando placeholder informativo."
    cat > "$dest" <<EOF
/* Placeholder generated at $NOW
   Legacy source not found in repository paths checked.
   Expected original file for this legacy entry:
   ${target}

   Si dispones del archivo original, reemplázalo por el contenido real.
*/
EOF
  fi
done

# Lista de paths a incluir (si existen) además de legacy ya generados en $TMPDIR
INCLUDE=(
  "package.json"
  "rollup.config.js"
  "src"
  "legacy"
  "apply_dom_utils_patch.sh"
  "create_dom_utils_patch_zip.sh"
)

# Copiar archivos/dirs existentes al TMP
for path in "${INCLUDE[@]}"; do
  if [ -e "$CWD/$path" ]; then
    echo "Incluir: $path"
    if [ -d "$CWD/$path" ]; then
      # copiar todo el directorio preservando estructura (pero no incluir node_modules por si acaso)
      rsync -a --exclude 'node_modules' "$CWD/$path" "$TMPDIR/" >/dev/null
    else
      mkdir -p "$TMPDIR/$(dirname "$path")"
      cp -p "$CWD/$path" "$TMPDIR/$path"
    fi
  else
    echo "No existe (se omite): $path"
  fi
done

# Añadir README-DOM-UTILS-PATCH.md
cat > "$TMPDIR/README-DOM-UTILS-PATCH.md" <<EOF
DOM Utils Consolidation Patch
-----------------------------

Generado: $NOW (UTC)

Este archivo contiene la consolidación propuesta de la librería:
 - package.json (actualizado con "exports" y subpath ./bottom-sheet)
 - rollup.config.js (actualizado para generar index.* y bottom-sheet.*)
 - src/ (entrypoint consolidado y módulos)
 - legacy/ (copias estandarizadas de los archivos antiguos o placeholders)
 - README-DOM-UTILS-PATCH.md (este archivo)
 - CHANGELOG.txt (resumen de cambios)

Instrucciones:
1) Extrae el zip:
   unzip $OUT_ZIP -d dom-utils-patch
2) Revisa los archivos en dom-utils-patch/
3) Ejecuta en la raíz:
   npm install
   npm run build
4) Si todo OK, crea branch y PR:
   git checkout -b chore/consolidate-dom-utils
   git add .
   git commit -m "chore: consolidate src and move legacy files to /legacy"
   git push origin chore/consolidate-dom-utils

EOF

# Añadir CHANGELOG.txt con resumen
cat > "$TMPDIR/CHANGELOG.txt" <<EOF
DOM Utils Consolidation Patch - CHANGELOG
Generated: $NOW (UTC)

Resumen:
- Consolidado src/index.js usando la versión modular (nueva).
- Reemplazado src/core/dom-extensions.js por versión extendida (chainable helpers, eventos, animaciones).
- Añadido src/ajax/index.js como adaptador de compatibilidad hacia modules/ajax.js (si aplica).
- Rollup configurado para outputs:
  - dist/index.esm.js, dist/index.cjs.js, dist/index.umd.js
  - dist/bottom-sheet.esm.js, dist/bottom-sheet.cjs.js
- package.json actualizado con "exports" para '.' y './bottom-sheet' y "sideEffects": false.
- bottom-sheet registra custom element de forma condicional (solo si window existe y no está registrado).
- Archivos duplicados/más antiguos movidos a legacy/ con nombres:
  - legacy/src/index.old.js
  - legacy/src/core/dom-extensions.old.js
  - legacy/src/ajax/fetch.old.js
  - legacy/rollup.config.old.js
  - legacy/src/core/bottom-sheet-base.old.js
  - legacy/src/core/bottom-sheet.old.js

Nota:
- Algunos legacy files pudieron no estar presentes en la repo; en tal caso se ha incluido un placeholder informativo en legacy/.
- Revisa los placeholders y reemplázalos por contenido real si los tienes.

EOF

# Crear el ZIP
echo "Creando ZIP: $OUT_ZIP"
if command -v zip >/dev/null 2>&1; then
  (cd "$TMPDIR" && zip -r "../$OUT_ZIP" . >/dev/null)
  mv "$TMPDIR/../$OUT_ZIP" "$CWD/$OUT_ZIP"
else
  echo "zip no disponible: intentando python3"
  python3 - <<PY
import os, zipfile, shutil, sys
root = "${TMPDIR}"
out = os.path.join("${CWD}", "${OUT_ZIP}")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for base, dirs, files in os.walk(root):
        for f in files:
            path = os.path.join(base, f)
            arcname = os.path.relpath(path, root)
            z.write(path, arcname)
print("Wrote", out)
PY
fi

echo "ZIP creado en: $CWD/$OUT_ZIP"
echo "Contenido (primeras 200 líneas):"
unzip -l "$OUT_ZIP" | sed -n '1,200p' || true

echo "Hecho. Revisa $OUT_ZIP y extrae para validar."