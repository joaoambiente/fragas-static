#!/usr/bin/env bash
set -euo pipefail

if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  cd "$git_root"
fi

echo "Cleaning static WordPress export..."

removed=()
remove_path() {
  local path="$1"

  if [[ -e "$path" ]]; then
    rm -rf "$path"
    removed+=("$path")
  fi
}

remove_path "meuloginfragas"
remove_path "wp-json"
remove_path "wp-admin"
remove_path "wp-content/plugins/wordfence"

html_files=()
while IFS= read -r -d '' file; do
  html_files+=("$file")
done < <(find . -type f -name '*.html' -not -path './.git/*' -print0)

if ((${#html_files[@]})); then
  perl -0pi -e '
    s{https?://fragaslocal\.local/?(?=[A-Za-z0-9_-])}{https://fragasaveloso.pt/}g;
    s{https?://fragaslocal\.local/?}{https://fragasaveloso.pt/}g;
    s{https://joaoambiente\.github\.io/fragas-static/?}{https://fragasaveloso.pt/}g;
    s{http://fragasaveloso\.pt/}{https://fragasaveloso.pt/}g;
    s{\s*<link rel="pingback" href="https://fragasaveloso\.pt/xmlrpc\.php" ?/?>}{}g;
    s{\s*<link rel="https://api\.w\.org/" href="https://fragasaveloso\.pt/wp-json/" ?/?>}{}g;
    s{\s*<link rel="alternate" title="JSON" type="application/json" href="https://fragasaveloso\.pt/wp-json/[^"]+" ?/?>}{}g;
    s{\s*<link rel="EditURI" type="application/rsd\+xml" title="RSD" href="https://fragasaveloso\.pt/xmlrpc\.php\?rsd" ?/?>}{}g;
    s{\s*<script type="speculationrules">.*?</script>}{}gs;
    s{\s*<script type="text/javascript" src="https://fragasaveloso\.pt/wp-includes/js/comment-reply\.min\.js\?ver=[^"]+" id="comment-reply-js"[^>]*></script>}{}g;
    s{\s*<div id="respond" class="comment-respond">.*?</div><!-- #respond -->}{}gs;
  ' "${html_files[@]}"
fi

if [[ -f robots.txt ]]; then
  perl -0pi -e '
    s{^Disallow: /wp-admin/\R}{}mg;
    s{^Allow: /wp-admin/admin-ajax\.php\R}{}mg;
  ' robots.txt

  if ! grep -qx 'Allow: /' robots.txt; then
    perl -0pi -e 's{User-agent: \*\R}{User-agent: *\nAllow: /\n}' robots.txt
  fi
fi

echo "Checking for blocked static-export artifacts..."

failed=0

check_paths=(
  "meuloginfragas"
  "wp-json"
  "wp-admin"
  "wp-content/plugins/wordfence"
)

for path in "${check_paths[@]}"; do
  if [[ -e "$path" ]]; then
    echo "ERROR: blocked path still exists: $path"
    failed=1
  fi
done

check_rg() {
  local label="$1"
  local pattern="$2"

  if rg --hidden --glob '!.git/**' --glob '!scripts/clean-static-export.sh' -n "$pattern" . >/tmp/fragas-static-check.txt; then
    echo "ERROR: $label"
    cat /tmp/fragas-static-check.txt
    failed=1
  fi
}

check_rg "found local/dev URLs or old GitHub Pages URLs" 'fragaslocal\.local|localhost|127\.0\.0\.1|joaoambiente\.github\.io/fragas-static'
check_rg "found insecure custom-domain URL" 'http://fragasaveloso\.pt'
check_rg "found removed WordPress endpoint references" '/meuloginfragas/|/wp-json/|/wp-admin/|wp-content/plugins/wordfence|xmlrpc\.php|wp-login\.php|admin-ajax\.php|load-styles\.php|load-scripts\.php'
check_rg "found likely secret material" 'DB_PASSWORD|AUTH_KEY|SECURE_AUTH_KEY|LOGGED_IN_KEY|NONCE_KEY|BEGIN [A-Z ]*PRIVATE KEY'

secret_files=()
while IFS= read -r -d '' file; do
  secret_files+=("$file")
done < <(
  find . -type f \
    -not -path './.git/*' \
    \( -name 'wp-config.php' -o -name '.env' -o -name '*.sql' -o -name '*.sql.gz' -o -name 'id_rsa' -o -name '*.pem' \) \
    -print0
)

if ((${#secret_files[@]})); then
  echo "ERROR: found likely secret/config files:"
  printf '%s\n' "${secret_files[@]}"
  failed=1
fi

rm -f /tmp/fragas-static-check.txt

if ((${#removed[@]})); then
  echo "Removed paths:"
  printf '  - %s\n' "${removed[@]}"
fi

if ((failed)); then
  echo "Static export cleanup finished with errors. Fix the items above before publishing."
  exit 1
fi

echo "Static export cleanup passed."
