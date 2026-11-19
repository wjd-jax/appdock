#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
compose=(docker compose -f deploy/compose.yaml -f test/team_distribution/compose.acceptance.yaml)
test -f ../checks/sample.apk || { printf 'Missing isolated sample APK: ../checks/sample.apk\n' >&2; exit 1; }
cp test/team_distribution/verify*.rb ../checks/

# Inspect the resolved configuration without printing credentials.
acceptance_https_port=$("${compose[@]}" config --format json | python3 -c '
import json,sys
c=json.load(sys.stdin); services=c["services"]
assert c["name"].startswith("appdock-acceptance"), "isolated Compose project required"
assert services["postgres"]["environment"]["POSTGRES_DB"]=="appdock_verify"
assert services["appdock"]["environment"]["APPDOCK_POSTGRES_DB_NAME"]=="appdock_verify"
assert len(services["web"]["ports"])==2
assert all(p.get("host_ip")=="127.0.0.1" for p in services["web"]["ports"])
port=next(p["published"] for p in services["web"]["ports"] if p["target"]==443)
assert str(port).isdigit() and 1024 <= int(port) <= 65535
assert services["appdock"]["environment"]["APPDOCK_DOMAIN"]=="apps.example.com:"+str(port)
print(port)
')
export APPDOCK_ACCEPTANCE_HTTPS_PORT="$acceptance_https_port"
printf 'PASS: isolated database and loopback HTTPS port %s\n' "$acceptance_https_port"

"${compose[@]}" exec -T appdock bin/rails zeitwerk:check
for script in verify.rb verify_package_links.rb verify_download_counts.rb verify_developer_setup.rb verify_udid.rb verify_lark.rb verify_network_access.rb verify_appdock_brand.rb verify_release_link_time.rb verify_environment_links.rb verify_deletion.rb; do
  printf 'Running %s\n' "$script"
  "${compose[@]}" exec -T -e APPDOCK_ACCEPTANCE_HTTPS_PORT="$acceptance_https_port" appdock bin/rails runner --skip-executor "/checks/$script"
done
ruby test/team_distribution/verify_appdock_environment.rb
ruby test/team_distribution/verify_legacy_tasks.rb
export APPDOCK_TEST_RESOLVE_HOST=apps.example.com
export PYTHONPATH="$PWD/test/team_distribution/support"
export APPDOCK_TEST_CA_CERT="$PWD/deploy/data/caddy/caddy/pki/authorities/local/root.crt"
test -f "$APPDOCK_TEST_CA_CERT" || { printf 'Missing isolated Caddy CA certificate\n' >&2; exit 1; }
python3 - <<'PY'
import http.client
import os
import ssl
for path in ['/api/health', '/workspace', '/developers', '/udid']:
    connection = http.client.HTTPSConnection('apps.example.com', int(os.environ['APPDOCK_ACCEPTANCE_HTTPS_PORT']), timeout=15,
                                            context=ssl.create_default_context())
    connection.request('GET', path)
    response = connection.getresponse()
    response.read()
    assert response.status == 200, (path, response.status)
    connection.close()
    print('PASS: trusted HTTPS ' + path)
PY
python3 test/team_distribution/verify_cli.py --endpoint "https://apps.example.com:$acceptance_https_port" --apk ../checks/sample.apk
printf 'All isolated Rails and compatibility checks passed\n'
