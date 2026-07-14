#!/usr/bin/env bash
#
# Fixture-driven tests for validate_catalog.swift.
# Compiles the validator once, then runs it against known good/bad catalogs and
# asserts the exit code (0 = valid, 1 = problems) and a expected message substring.
#
set -uo pipefail
cd "$(dirname "$0")"                       # Tools/
FIX=validate_catalog_fixtures

BIN="$(mktemp -d)/validate_catalog"
echo "compiling validate_catalog.swift…"
if ! swiftc -o "$BIN" validate_catalog.swift; then
    echo "COMPILE FAILED"; exit 1
fi

pass=0; failn=0

# run <name> <expect_exit> <expect_substr> -- <args-to-validator...>
run() {
    local name=$1 exp=$2 substr=$3; shift 3; [ "${1:-}" = "--" ] && shift
    local out rc ok=1
    out="$("$BIN" "$@" 2>&1)"; rc=$?
    [ "$rc" -eq "$exp" ] || ok=0
    if [ -n "$substr" ] && ! grep -qi -- "$substr" <<<"$out"; then ok=0; fi
    if [ $ok -eq 1 ]; then
        pass=$((pass+1)); printf '  PASS  %s\n' "$name"
    else
        failn=$((failn+1)); printf '  FAIL  %s (rc=%s, expected=%s)\n---\n%s\n---\n' "$name" "$rc" "$exp" "$out"
    fi
}

echo "valid catalogs (expect exit 0):"
run valid                 0 "catalog valid"    -- "$FIX/valid.json"   # note: valid.json's credit is "Photo by Jane Doe" — a name in a credit passes
run valid_unknown_type    0 "catalog valid"    -- "$FIX/valid_unknown_type.json"
run valid_with_assets     0 "catalog valid"    -- "$FIX/valid.json" "$FIX/assets"
run denylist_off_passes   0 "catalog valid"    -- "$FIX/denylist_target.json"

echo "invalid catalogs (expect exit 1):"
run dup_site_id           1 "duplicate site id"  -- "$FIX/dup_site_id.json"
run dup_photo_id          1 "duplicate photo id" -- "$FIX/dup_photo_id.json"
run unknown_city          1 "cityId"             -- "$FIX/unknown_city.json"
run lat_out_of_range      1 "lat"                -- "$FIX/lat_out_of_range.json"
run lon_out_of_range      1 "lon"                -- "$FIX/lon_out_of_range.json"
run bad_country           1 "ISO 3166"           -- "$FIX/bad_country.json"
run bad_semantic_tag      1 "semanticTag"        -- "$FIX/bad_semantic_tag.json"
run bad_era               1 "era"                -- "$FIX/bad_era.json"
run bad_importance        1 "importance"         -- "$FIX/bad_importance.json"
run added_version_high    1 "addedInVersion"     -- "$FIX/added_version_too_high.json"
run email_leak            1 "email"              -- "$FIX/email_leak.json"
run malformed_json        1 "schema"             -- "$FIX/malformed.json"
run missing_field         1 "schema"             -- "$FIX/missing_field.json"
run missing_thumb         1 "thumb"              -- "$FIX/missing_thumb.json" "$FIX/assets"

echo "denylist (opt-in, env-supplied):"
# Same fixture that PASSES above must FAIL once the denylist names the handle.
out="$(CATALOG_DENYLIST="$FIX/denylist_sample.txt" "$BIN" "$FIX/denylist_target.json" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qi "denylisted" <<<"$out"; then
    pass=$((pass+1)); printf '  PASS  %s\n' "denylist_on_fails"
else
    failn=$((failn+1)); printf '  FAIL  %s (rc=%s)\n---\n%s\n---\n' "denylist_on_fails" "$rc" "$out"
fi

echo
echo "results: $pass passed, $failn failed"
[ $failn -eq 0 ] || exit 1
echo "ALL VALIDATOR TESTS PASSED"
