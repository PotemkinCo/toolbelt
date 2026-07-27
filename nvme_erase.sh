#!/usr/bin/env bash
set -uo pipefail

LOGFILE="/root/nvme_wipe_report_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== NVMe drives and capacities ==="
nvme list

DEVICES=$(nvme list -o json 2>/dev/null | grep -oP '"DevicePath"\s*:\s*"\K[^"]+' || lsblk -dno NAME | grep '^nvme' | sed 's|^|/dev/|')

declare -A RESULTS

for dev in $DEVICES; do
  ctrl="${dev%n*}"
  echo "--- Processing $dev (controller: $ctrl) ---"

  echo "Capturing pre-erase security capability flags..."
  CAPS_BEFORE=$(nvme id-ctrl "$ctrl" -H 2>/dev/null | grep -A6 "sanicap")
  echo "$CAPS_BEFORE"
  RESULTS["$dev:sanicap_before"]="$(echo "$CAPS_BEFORE" | tr '\n' ' ')"

  sanitize_supported=0
  crypto_erase_supported=0
  block_erase_supported=0

  echo "$CAPS_BEFORE" | grep -qi "Crypto Erase Sanitize Operation Supported" && sanitize_supported=1 && crypto_erase_supported=1
  echo "$CAPS_BEFORE" | grep -qi "Block Erase Sanitize Operation Supported" && block_erase_supported=1
  nvme id-ctrl "$ctrl" -H 2>/dev/null | grep -qi "Crypto Erase Supported" && crypto_erase_supported=1

  RESULTS["$dev:flag_sanitize_crypto"]="$sanitize_supported"
  RESULTS["$dev:flag_sanitize_block"]="$block_erase_supported"
  RESULTS["$dev:flag_crypto_erase"]="$crypto_erase_supported"

  success=0
  method=""

  if [ "$sanitize_supported" -eq 1 ]; then
    method="sanitize-crypto-erase"
    echo "Starting Sanitize crypto-erase on $ctrl"
    nvme sanitize "$ctrl" -a start-crypto-erase
    for i in $(seq 1 120); do
      log=$(nvme sanitize-log "$dev" 2>/dev/null)
      sstat=$(echo "$log" | grep -oP 'Status.*?:\s*\K0x[0-9a-fA-F]+' | head -1)
      sprog=$(echo "$log" | grep -oP 'Progress.*?:\s*\K[0-9]+' | head -1)
      echo "  [$i] SPROG=$sprog SSTAT=$sstat"
      [[ "$sstat" == "0x101" ]] && { success=1; break; }
      [[ "$sstat" == "0x103" ]] && { echo "  Sanitize FAILED"; break; }
      sleep 5
    done
    RESULTS["$dev:sanitize_final_sstat"]="$sstat"

  elif [ "$crypto_erase_supported" -eq 1 ]; then
    method="format-crypto-erase"
    nvme format "$dev" -s 2 --force && success=1

  else
    method="format-user-data-erase"
    nvme format "$dev" -s 1 --force && success=1
  fi

  RESULTS["$dev:erase"]="$method:$success"

  echo "Running secure blkdiscard on $dev"
  if blkdiscard --secure "$dev" 2>/dev/null; then
    RESULTS["$dev:discard"]="secure-ok"
  elif blkdiscard "$dev" 2>/dev/null; then
    RESULTS["$dev:discard"]="ok"
  else
    RESULTS["$dev:discard"]="FAILED"
  fi

  echo "Capturing post-erase security capability flags (confirming drive state unchanged/consistent)..."
  CAPS_AFTER=$(nvme id-ctrl "$ctrl" -H 2>/dev/null | grep -A6 "sanicap")
  RESULTS["$dev:sanicap_after"]="$(echo "$CAPS_AFTER" | tr '\n' ' ')"

  echo "Verifying full-disk sample for non-zero data (this may take a while)..."
  size_bytes=$(blockdev --getsize64 "$dev")
  size_mb=$((size_bytes / 1024 / 1024))
  sample_mb=$((size_mb < 2048 ? size_mb : 2048))
  nonzero=$(dd if="$dev" bs=1M count="$sample_mb" 2>/dev/null | tr -d '\0' | wc -c)
  if [ "$nonzero" -eq 0 ]; then
    RESULTS["$dev:verify"]="PASS (${sample_mb}MB sample all zero)"
  else
    RESULTS["$dev:verify"]="FAIL ($nonzero non-zero bytes in ${sample_mb}MB sample)"
  fi

  echo "Confirming device is unmounted/unpartitioned..."
  lsblk "$dev" -o NAME,FSTYPE,MOUNTPOINT
done

echo ""
echo "=== FINAL SUMMARY ==="
for dev in $DEVICES; do
  echo "Device: $dev"
  echo "  Sanitize crypto-erase supported : ${RESULTS[$dev:flag_sanitize_crypto]}"
  echo "  Sanitize block-erase supported  : ${RESULTS[$dev:flag_sanitize_block]}"
  echo "  Crypto erase (format) supported : ${RESULTS[$dev:flag_crypto_erase]}"
  echo "  Erase method used               : ${RESULTS[$dev:erase]}"
  echo "  Sanitize final SSTAT            : ${RESULTS[$dev:sanitize_final_sstat]:-N/A}"
  echo "  blkdiscard result               : ${RESULTS[$dev:discard]}"
  echo "  Data sample verification        : ${RESULTS[$dev:verify]}"
  echo "---"
done
echo ""
echo "Full log saved to: $LOGFILE"
