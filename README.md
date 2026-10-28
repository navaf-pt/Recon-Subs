# ReconSubs

<img width="965" height="524" alt="Screenshot From 2026-10-29 01-45-42" src="https://github.com/user-attachments/assets/6a8f156a-a646-46ab-9d16-c523d523a308" />

A small Bash tool for collecting passive subdomain results from locally installed tools and public, no-key sources. It validates that hostnames belong to the requested target, normalizes them, and writes one deduplicated text file.

Use it only on domains you own or are authorized to assess.

## Requirements

- Bash 4+
- `curl`, `grep`, `awk`, `sed`, `sort`, and `timeout`

ReconSub automatically uses any of these optional tools that are installed:

- `subfinder`
- `amass`
- `assetfinder`
- `findomain`
- `sublist3r`

Wayback Machine results are collected directly through its public CDX API and require no additional tool.

Check availability with:

```bash
./reconsub.sh --check
```

## Usage

Download
```bash
git clone https://github.com/navaf-pt/Recon-Subs.git
```

Make the script executable once:

```bash
chmod +x reconsub.sh
```

Collect subdomains for one domain:

```bash
./reconsub.sh example.com
```

The final output is written to `subdomains.txt` in the current directory.

Choose a different output filename:

```bash
./reconsub.sh -o example-subs.txt -d example.com
```

Process a list of domains (one per line) into one combined output file:

```bash
./reconsub.sh -l domains.txt -o subdomains.txt
```

Increase the per-source timeout when a passive source is slow:

```bash
./reconsub.sh --timeout 120 -d example.com
```

## How it works

1. Runs each available source one at a time.
2. Stores source captures only in temporary files.
3. Extracts hostname candidates from URL/API responses.
4. Normalizes case and removes certificate wildcards (`*.`).
5. Retains only valid hostnames matching the target or a dot-bounded subdomain suffix.
6. Uses `sort -u` to create the final unique result file.

Temporary files are removed on normal exit or interruption. No API keys, probing, port scanning, crawling, or vulnerability checks are included.

## Options

```text
-d, --domain DOMAIN    One domain
-l, --list FILE        File containing one domain per line
-o, --output FILE      Final text file (default: subdomains.txt)
    --timeout NUM      Per-source timeout in seconds (default: 60)
    --check            Show available local tools
    --quiet            Suppress progress messages
    --verbose          Show source errors
    --version          Show version
-h, --help             Show help
```
