#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
compose=(docker compose -f deploy/compose.yaml -f test/team_distribution/compose.acceptance.yaml)
test -f ../checks/sample.apk || { printf 'Missing isolated sample APK: ../checks/sample.apk\n' >&2; exit 1; }
cp test/team_distribution/verify*.rb ../checks/

# Inspect the resolved configuration without printing credentials.
"${compose[@]}" config --format json | python3 -c '
import json,sys
c=json.load(sys.stdin); services=c["services"]
assert c["name"].startswith("appdock-acceptance"), "isolated Compose project required"
assert services["postgres"]["environment"]["POSTGRES_DB"]=="appdock_verify"
assert services["appdock"]["environment"]["APPDOCK_POSTGRES_DB_NAME"]=="appdock_verify"
assert len(services["web"]["ports"])==2
assert all(p.get("host_ip")=="127.0.0.1" for p in services["web"]["ports"])
print("PASS: isolated database and loopback web ports")
'

"${compose[@]}" exec -T appdock bin/rails zeitwerk:check
for script in verify.rb verify_developer_setup.rb verify_udid.rb verify_lark.rb verify_network_access.rb verify_appdock_brand.rb; do
  printf 'Running %s\n' "$script"
  "${compose[@]}" exec -T appdock bin/rails runner --skip-executor "/checks/$script"
done
ruby test/team_distribution/verify_appdock_environment.rb
ruby test/team_distribution/verify_legacy_tasks.rb
export APPDOCK_TEST_RESOLVE_HOST=apps.example.com
export PYTHONPATH="$PWD/test/team_distribution/support"
export APPDOCK_TEST_CA_CERT="$PWD/deploy/data/caddy/caddy/pki/authorities/local/root.crt"
test -f "$APPDOCK_TEST_CA_CERT" || { printf 'Missing isolated Caddy CA certificate\n' >&2; exit 1; }
python3 - <<'PY'
import http.client
import ssl
for path in ['/api/health', '/workspace', '/developers', '/udid']:
    connection = http.client.HTTPSConnection('apps.example.com', 18443, timeout=15,
                                            context=ssl.create_default_context())
    connection.request('GET', path)
    response = connection.getresponse()
    response.read()
    assert response.status == 200, (path, response.status)
    connection.close()
    print('PASS: trusted HTTPS ' + path)
PY
python3 test/team_distribution/verify_cli.py --endpoint https://apps.example.com:18443 --apk ../checks/sample.apk
printf 'All isolated Rails and compatibility checks passed\n'
