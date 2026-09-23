#!/usr/bin/env bash
# Upload bcjiraintegration to the Production environment via the BC automation API
# (equivalent to Extension Management > Upload Extension; NOT a dev publish).
# Usage: bash deploy-prod.sh [path-to-.app]
set -euo pipefail
cd "$(dirname "$0")"

TENANT=7e6efb3b-5060-4666-aee5-ffe6f3cb3644          # Integrated Technologies
ENVIRONMENT=Production
COMPANY_ID=7695d01d-d042-f111-a820-7ced8d71cbf2       # Integrated Technologies OÜ
APP="${1:-$(ls app/integrated.ee_bcjiraintegration_*.app | sort -V | tail -1)}"
BASE="https://api.businesscentral.dynamics.com/v2.0/$TENANT/$ENVIRONMENT/api/microsoft/automation/v2.0"

echo "Deploying $APP to $ENVIRONMENT"
TOK=$(az account get-access-token --resource https://api.businesscentral.dynamics.com --tenant "$TENANT" --query accessToken -o tsv)

SID=$(curl -sf -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
  -d '{"schedule":"Current version","schemaSyncMode":"Add"}' \
  "$BASE/companies($COMPANY_ID)/extensionUpload" | python -c "import sys,json; print(json.load(sys.stdin)['systemId'])")
echo "upload record: $SID"

curl -sf -o /dev/null -X PATCH -H "Authorization: Bearer $TOK" -H "If-Match: *" \
  -H "Content-Type: application/octet-stream" --data-binary "@$APP" \
  "$BASE/companies($COMPANY_ID)/extensionUpload($SID)/extensionContent"
echo "content uploaded"

curl -sf -o /dev/null -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d '{}' \
  "$BASE/companies($COMPANY_ID)/extensionUpload($SID)/Microsoft.NAV.upload"
echo "deployment started; polling..."

VERSION=$(basename "$APP" .app | sed 's/.*_//')
for i in $(seq 1 60); do
  sleep 10
  STATUS=$(curl -s -H "Authorization: Bearer $TOK" "$BASE/companies($COMPANY_ID)/extensionDeploymentStatus" | python -c "
import sys,json
# The list is not in date order and may hold older attempts at the same version: take the newest.
v=sorted((e for e in json.load(sys.stdin)['value'] if e.get('appVersion')=='$VERSION'), key=lambda e: e.get('startedOn',''))
print(v[-1]['status'] if v else 'pending')")
  echo "  $STATUS"
  case "$STATUS" in Completed|Failed) break;; esac
done

echo "== installed version now:"
curl -s -H "Authorization: Bearer $TOK" "$BASE/companies($COMPANY_ID)/extensions" | python -c "
import sys,json
for e in json.load(sys.stdin)['value']:
    if e['publisher']=='integrated.ee':
        print(e['displayName'], '%d.%d.%d.%d' % (e['versionMajor'],e['versionMinor'],e['versionBuild'],e['versionRevision']), 'installed=',e['isInstalled'])"
