#!/bin/sh

# Resolve a Python interpreter without baking one developer's home directory
# into every scientific harness. Set PYTHON=/path/to/python to override.
resolve_mac4dstem_python() {
  repo_root=$1
  for candidate in \
    "${PYTHON:-}" \
    "${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/python}" \
    "${CONDA_PREFIX:+$CONDA_PREFIX/bin/python}" \
    "$repo_root/.venv/bin/python" \
    "$HOME/miniconda3/envs/py4dstem/bin/python" \
    "$HOME/anaconda3/envs/py4dstem/bin/python"
  do
    if [ -n "$candidate" ] && [ -x "$candidate" ] \
      && "$candidate" -c 'import numpy' >/dev/null 2>&1; then
      PYTHON_BIN=$candidate
      export PYTHON_BIN
      return 0
    fi
  done
  if command -v python3 >/dev/null 2>&1 \
    && python3 -c 'import numpy' >/dev/null 2>&1; then
    PYTHON_BIN=$(command -v python3)
    export PYTHON_BIN
    return 0
  fi
  echo "No Python interpreter with NumPy found. Set PYTHON=/path/to/python." >&2
  return 1
}
