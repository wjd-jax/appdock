#!/usr/bin/env python3
"""Use only with the isolated verification URL/channel and a public test APK."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--endpoint',required=True)
p.add_argument('--channel-key',help='Legacy option, unused by automatic uploads')
p.add_argument('--apk',required=True)
a=p.parse_args()
if not a.endpoint.endswith(':18443'): raise SystemExit('Refusing non-verification endpoint')
cli=Path(__file__).resolve().parents[2]/'tools/team_release.py'
apk=Path(a.apk).resolve()
with tempfile.TemporaryDirectory(prefix='team-cli-check-') as tmp:
    root=Path(tmp)
    cfg={'endpoint':a.endpoint,'build':[sys.executable,'-c','import shutil; shutil.copyfile('+repr(str(apk))+', "test.apk")'],'artifact':'test.apk'}
    (root/'.team-distribution.json').write_text(json.dumps(cfg))
    def run(command,success):
        r=subprocess.run([sys.executable,str(cli),*command],cwd=root,capture_output=True,text=True)
        assert (r.returncode==0)==success,(r.returncode,r.stderr)
        return json.loads(r.stdout if success else r.stderr.strip().splitlines()[-1])
    result=run(['release'],True)
    assert result['file_sha256'] and result['duplicate'] is True and 'share=' not in result['release_url']
    print('PASS: configured fixture build + token-free API upload + structured links + dedupe')
    cfg['build']=[sys.executable,'-c','raise SystemExit(7)'];(root/'.team-distribution.json').write_text(json.dumps(cfg))
    assert '构建失败' in run(['release'],False)['error']
    print('PASS: failed build never uploads')
    cfg['build']=[sys.executable,'-c','pass'];cfg['artifact']='missing.apk';(root/'.team-distribution.json').write_text(json.dumps(cfg))
    assert '0 个' in run(['release'],False)['error']
    print('PASS: missing artifact rejected')
    cfg['artifact']='*.apk';(root/'second.apk').write_bytes(b'not an app');(root/'.team-distribution.json').write_text(json.dumps(cfg))
    assert '2 个' in run(['upload'],False)['error']
    print('PASS: ambiguous artifact rejected')
    cfg['endpoint']='http://apps.example.com';cfg['artifact']='test.apk';(root/'.team-distribution.json').write_text(json.dumps(cfg))
    assert 'HTTPS' in run(['upload'],False)['error']
    print('PASS: untrusted HTTP endpoint rejected')
print('CLI verification complete')
