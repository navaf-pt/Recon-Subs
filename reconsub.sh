#!/usr/bin/env bash
# reconsub.sh - small raw subdomain collection helper

set -u

VERSION="1.0.0"
OUTFILE=""
TIMEOUT=300
QUIET=0
VERBOSE=0
TMPDIRS=()

usage() {
  cat <<'EOF'
Usage: reconsub.sh [options] DOMAIN

Collect, validate, and deduplicate subdomains into one text file.

  -d, --domain DOMAIN    One domain
  -l, --list FILE        File containing one domain per line
  -o, --output FILE      Final text file (default: subdomains.txt)
      --timeout NUM      Per-source timeout in seconds (default: 300)
      --check            Show available local tools
      --quiet            Suppress progress messages
      --verbose          Show failed source details
      --version          Show version
  -h, --help             Show this help

EOF
}

log() {
  local message=$*
  (( QUIET )) && return
  if [[ ! -t 2 ]]; then
    printf '%s\n' "$message" >&2
    return
  fi
  case $message in
    '[✓] Unique subdomains:'*) printf '\033[1;33m%s\033[0m\n' "$message" >&2 ;;
    '[✓] Results saved:'*)     printf '\033[1;32m%s\033[0m\n' "$message" >&2 ;;
    '    '*)                   printf '\033[1;32m%s\033[0m\n' "$message" >&2 ;;
    '[✓]'*)                    printf '\033[1;32m%s\033[0m\n' "$message" >&2 ;;
    '[!]'*)                    printf '\033[1;33m%s\033[0m\n' "$message" >&2 ;;
    '[+]'*)                    printf '\033[1;36m%s\033[0m\n' "$message" >&2 ;;
    *)                         printf '%s\n' "$message" >&2 ;;
  esac
}
banner() {
  (( QUIET )) && return
  [[ -t 2 ]] && printf '\033[1;32m' >&2
  cat >&2 <<'EOF'
╔══════════════════════════════════════════════════════════════════════╗
║    _____ _   _ ____      ______ _   _ _   _ __  __                   ║
║   / ____| | | |  _ \    |  ____| \ | | | | |  \/  |                  ║
║  | (___ | | | | |_) |   | |__  |  \| | | | | \  / |                  ║
║   \___ \| | | |  _ <    |  __| | . ` | | | | |\/| |                  ║
║   ____) | |_| | |_) |   | |____| |\  | |_| | |  | |                  ║
║  |_____/ \___/|____/    |______|_| \_|\___/|_|  |_|                  ║
║                       By github.com/navaf-pt                         ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
  [[ -t 2 ]] && printf '\033[0m' >&2
}
cleanup() { local d; for d in "${TMPDIRS[@]:-}"; do [[ -n $d ]] && rm -rf -- "$d"; done; }
trap cleanup EXIT
trap 'exit 130' INT TERM

need_number() { [[ $1 =~ ^[1-9][0-9]*$ ]]; }
command_available() { command -v "$1" >/dev/null 2>&1; }
valid_target() { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; }

check_tools() {
  local tool
  for tool in subfinder amass assetfinder findomain sublist3r; do
    if command_available "$tool"; then printf '[+] %s available\n' "$tool"; else printf '[!] %s not installed\n' "$tool"; fi
  done
}

# Each function writes only its raw response/output to its assigned file.
source_subfinder() { subfinder -d "$1" -silent; }
source_amass() { amass enum -passive -d "$1"; }
source_assetfinder() { assetfinder --subs-only "$1"; }
source_findomain() { findomain -t "$1" -q; }
source_sublist3r() {
  python3 -c '
import multiprocessing
multiprocessing.set_start_method("fork", force=True)
import sys
import sublist3r
for subdomain in sublist3r.main(sys.argv[1], 40, None, False, True, False, False, None):
    print(subdomain)
' "$1"
}
source_waybackmachine() {
  curl -fsSL --max-time "$TIMEOUT" -A "ReconSub/1.0" \
    "https://web.archive.org/cdx/search/cdx?url=*.$1/*&output=txt&fl=original&collapse=urlkey&filter=statuscode:200" |
  python3 -c '
import sys
from urllib.parse import urlsplit
for line in sys.stdin:
    url = line.strip()
    if url:
        host = urlsplit(url).hostname if "://" in url else url.split("/", 1)[0].split(":", 1)[0]
        if host:
            print(host.lower())
'
}
source_crtsh() { curl -fsSL --max-time "$TIMEOUT" "https://crt.sh/?q=%25.${1}&output=json" | grep -o '"name_value":"[^"]*"' | cut -d'"' -f4; }
source_certspotter() { curl -fsSL --max-time "$TIMEOUT" "https://api.certspotter.com/v1/issuances?domain=${1}&include_subdomains=true&expand=dns_names" | grep -oE '"[A-Za-z0-9*_.-]+\.[A-Za-z0-9_.-]+"' | tr -d '"'; }
source_hackertarget() { curl -fsSL --max-time "$TIMEOUT" "https://api.hackertarget.com/hostsearch/?q=${1}" | cut -d, -f1; }

source_label() {
  case $1 in
    subfinder) printf 'Subfinder' ;;
    amass) printf 'Amass' ;;
    assetfinder) printf 'Assetfinder' ;; findomain) printf 'Findomain' ;;
    sublist3r) printf 'Sublist3r' ;;
    waybackmachine) printf 'Wayback Machine' ;; crtsh) printf 'crt.sh' ;;
    certspotter) printf 'CertSpotter' ;; hackertarget) printf 'HackerTarget' ;;
    *) printf '%s' "$1" ;;
  esac
}

run_source() {
  local source=$1 domain=$2 file=$3 command=$4 status=$5 exit_code
  if [[ $command != curl ]] && ! command_available "$command"; then
    log "[!] $source not installed - skipping"
    printf '%s\tskipped\n' "$source" >>"$status"
    return
  fi
  if TIMEOUT="$TIMEOUT" timeout --signal=TERM --kill-after=5s "$TIMEOUT" bash -c 'eval "$1"; "$2" "$3"' bash \
      "$(declare -f "source_$source")" "source_$source" "$domain" >"$file" 2>"$file.err"; then
    log "[✓] $(printf '%-15s' "$(source_label "$source")") → $(wc -l <"$file")"
    printf '%s\tsuccess\n' "$source" >>"$status"
  else
    exit_code=$?
    # Preserve useful partial results produced before a slow source timed out.
    if (( exit_code == 124 || exit_code == 137 )) && [[ -s $file ]]; then
      log "[✓] $(printf '%-15s' "$(source_label "$source")") → $(wc -l <"$file") (partial)"
      printf '%s\tsuccess\n' "$source" >>"$status"
    else
      if (( VERBOSE )); then
        if (( exit_code == 124 || exit_code == 137 )); then
          log "[!] $(source_label "$source") timed out after ${TIMEOUT}s"
        else
          log "[!] $(source_label "$source") failed"
        fi
        sed 's/^/    /' "$file.err" >&2
      fi
      printf '%s\tfailed\n' "$source" >>"$status"
    fi
  fi
  rm -f -- "$file.err"
}

queue_source() {
  local source=$1 domain=$2 target=$3 command=$4
  run_source "$source" "$domain" "$target/$source.txt" "$command" "$target/status.txt"
}

enumerate_domain() {
  local domain=$1 master=$2 scope=$3 target
  if ! valid_target "$domain"; then
    printf 'Invalid domain: %s (use a full domain, e.g. starhealth.in)\n' "$domain" >&2
    return 2
  fi
  target=$(mktemp -d "${TMPDIR:-/tmp}/reconsub.XXXXXX") || return 1
  TMPDIRS+=("$target")
  : >"$target/status.txt"
  printf '%s\n' "$domain" >>"$scope"
  log "[+] Target: $domain"
  log "[+] Running passive enumeration..."
  queue_source subfinder "$domain" "$target" subfinder
  queue_source amass "$domain" "$target" amass
  queue_source assetfinder "$domain" "$target" assetfinder
  queue_source findomain "$domain" "$target" findomain
  queue_source sublist3r "$domain" "$target" sublist3r
  queue_source waybackmachine "$domain" "$target" curl
  queue_source crtsh "$domain" "$target" curl
  queue_source certspotter "$domain" "$target" curl
  queue_source hackertarget "$domain" "$target" curl
  cat -- "$target"/*.txt 2>/dev/null >>"$master" || true
}

write_output() {
  local master=$1 scope=$2 output=$3
  log "[+] Merging results..."
  log "[+] Normalizing..."
  log "[+] Validating scope..."
  log "[+] Removing duplicates..."
  # A valid hostname has two or more labels; labels cannot begin/end with a hyphen.
  if awk -v scope_file="$scope" '
    BEGIN {
      while ((getline domain < scope_file) > 0) allowed[tolower(domain)] = 1
      close(scope_file)
    }
    function valid(host, parts, count, i, label) {
      if (length(host) > 253) return 0
      count = split(host, parts, ".")
      if (count < 2) return 0
      for (i = 1; i <= count; i++) {
        label = parts[i]
        if (length(label) < 1 || length(label) > 63 ||
            label !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) return 0
      }
      return 1
    }
    function in_scope(host, lower_host, domain) {
      lower_host = tolower(host)
      for (domain in allowed) {
        if (lower_host == domain ||
            (length(lower_host) > length(domain) &&
             substr(lower_host, length(lower_host) - length(domain), length(domain) + 1) == "." domain)) return 1
      }
      return 0
    }
    {
      host = tolower($0)
      sub(/\r$/, "", host)
      sub(/^\*\./, "", host)
      if (valid(host) && in_scope(host)) print host
    }
  ' "$master" | LC_ALL=C sort -u >"$output"; then
    log "[✓] Unique subdomains: $(wc -l <"$output")"
    log "[✓] Results saved:"
    log "    $output"
  else
    printf 'Cannot write output file: %s\n' "$output" >&2
    return 1
  fi
}

DOMAIN="" LIST=""
RUN_FAILED=0
while (($#)); do
  case $1 in
    -d|--domain) DOMAIN=${2:-}; shift 2 ;;
    -l|--list) LIST=${2:-}; shift 2 ;;
    -o|--output) OUTFILE=${2:-}; shift 2 ;;
    --timeout) TIMEOUT=${2:-}; shift 2 ;;
    --check) check_tools; exit 0 ;;
    --quiet) QUIET=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    --version) printf 'reconsub %s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) [[ -z $DOMAIN ]] || { printf 'Only one positional domain is allowed\n' >&2; exit 2; }; DOMAIN=$1; shift ;;
  esac
done
need_number "$TIMEOUT" || { printf 'timeout must be a positive integer\n' >&2; exit 2; }
[[ -z $DOMAIN || -z $LIST ]] || { printf 'Use either --domain or --list, not both\n' >&2; exit 2; }
MASTER_FILE=$(mktemp "${TMPDIR:-/tmp}/reconsub-master.XXXXXX") || exit 1
TMPDIRS+=("$MASTER_FILE")
SCOPE_FILE=$(mktemp "${TMPDIR:-/tmp}/reconsub-scope.XXXXXX") || exit 1
TMPDIRS+=("$SCOPE_FILE")
banner
if [[ -n $LIST ]]; then
  [[ -r $LIST ]] || { printf 'Cannot read list: %s\n' "$LIST" >&2; exit 2; }
  while IFS= read -r DOMAIN || [[ -n $DOMAIN ]]; do
    [[ -z $DOMAIN ]] || enumerate_domain "$DOMAIN" "$MASTER_FILE" "$SCOPE_FILE" || RUN_FAILED=1
  done <"$LIST"
elif [[ -n $DOMAIN ]]; then
  enumerate_domain "$DOMAIN" "$MASTER_FILE" "$SCOPE_FILE" || exit $?
else
  usage >&2; exit 2
fi
(( RUN_FAILED == 0 )) || exit 2
write_output "$MASTER_FILE" "$SCOPE_FILE" "${OUTFILE:-subdomains.txt}"
