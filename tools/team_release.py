#!/usr/bin/env python3
"""团队分发：确定性构建与流式上传。仅使用 Python 标准库。"""
import argparse
import glob
import http.client
import json
import mimetypes
import os
from pathlib import Path
import secrets
import ssl
import subprocess
import sys
import time
from urllib.parse import urlsplit

class ReleaseError(Exception):
    pass

def git(args):
    try:
        p = subprocess.run(['git', *args], capture_output=True, text=True)
        return p.stdout.strip() if p.returncode == 0 else ''
    except FileNotFoundError:
        return ''

def config(path):
    p = Path(path)
    return json.loads(p.read_text()) if p.is_file() else {}

def upload(endpoint, token, artifact, fields, retries=2):
    url = urlsplit(endpoint.rstrip('/') + '/api/apps/upload')
    if url.scheme != 'https' or not url.hostname or url.username or url.password:
        raise ReleaseError('endpoint 必须是有效的 HTTPS 地址，不能内嵌凭据')
    boundary = 'TeamRelease' + secrets.token_hex(16)
    prefix = bytearray()
    for key, value in fields.items():
        if value is not None and str(value) != '':
            prefix.extend((f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n').encode())
    filename = artifact.name.replace('"','_').replace('\r','_').replace('\n','_')
    prefix.extend((f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\nContent-Type: {mimetypes.guess_type(filename)[0] or "application/octet-stream"}\r\n\r\n').encode())
    suffix = f'\r\n--{boundary}--\r\n'.encode()
    length = len(prefix) + artifact.stat().st_size + len(suffix)
    for attempt in range(retries + 1):
        connection = http.client.HTTPSConnection(url.hostname, url.port or 443, timeout=1800, context=ssl.create_default_context())
        try:
            connection.putrequest('POST', url.path)
            if token:
                connection.putheader('Authorization', 'Bearer ' + token)
            connection.putheader('Content-Type', 'multipart/form-data; boundary=' + boundary)
            connection.putheader('Content-Length', str(length))
            connection.putheader('Accept', 'application/json')
            connection.endheaders()
            connection.send(prefix)
            with artifact.open('rb') as stream:
                while chunk := stream.read(1024 * 1024):
                    connection.send(chunk)
            connection.send(suffix)
            response = connection.getresponse()
            body = response.read()
            try:
                result = json.loads(body)
            except ValueError:
                raise ReleaseError(f'服务器返回 HTTP {response.status}，未返回 JSON；请检查域名和登录配置')
            if response.status not in (200, 201):
                raise ReleaseError(f'上传失败 HTTP {response.status}: {result.get("error", "未知错误")}')
            required = ('id', 'release_url', 'qrcode_url')
            if not all(key in result for key in required):
                raise ReleaseError('服务器响应缺少版本链接字段')
            return {key: result.get(key) for key in ('id','app_name','release_version','build_version','platform','release_url','qrcode_url','install_url','app_url','environment_url','file_sha256','duplicate')}
        except (OSError, http.client.HTTPException) as error:
            if attempt >= retries:
                raise ReleaseError(f'网络上传失败：{type(error).__name__}；请确认处于公司网络') from None
            print(f'网络中断，准备重试 {attempt+1}/{retries}；相同文件会检查去重。', file=sys.stderr)
            time.sleep(min(2 ** attempt, 5))
        finally:
            connection.close()

def run(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default='.team-distribution.json')
    sub = parser.add_subparsers(dest='command', required=True)
    init = sub.add_parser('init', help='创建项目配置模板，不会覆盖已有文件')
    init.add_argument('--platform', choices=['android','ios','flutter','custom'], default='custom')
    for name in ('upload','release'):
        p = sub.add_parser(name, help='上传已有包' if name=='upload' else '先按配置构建，再上传')
        p.add_argument('file', nargs='?')
        p.add_argument('--endpoint')
        p.add_argument('--channel-key', help=argparse.SUPPRESS)
        p.add_argument('--changelog')
        p.add_argument('--allow-duplicate', action='store_true')
    args = parser.parse_args(argv)
    if args.command == 'init':
        builds = {'android':['./gradlew','assembleDebug'], 'flutter':['flutter','build','apk','--debug'], 'ios':['bundle','exec','fastlane','build_test'], 'custom':[]}
        artifacts = {'android':'app/build/outputs/apk/debug/*.apk','flutter':'build/app/outputs/flutter-apk/app-debug.apk','ios':'build/*.ipa','custom':'build/*.apk'}
        data={'endpoint':'https://apps.example.com','build':builds[args.platform],'artifact':artifacts[args.platform]}
        p=Path(args.config)
        if p.exists(): raise ReleaseError('配置文件已经存在，未覆盖')
        p.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
        print(json.dumps({'created':str(p),'next':'核对构建命令和产物路径，再执行 release'},ensure_ascii=False))
        return
    cfg=config(args.config)
    token=os.environ.get('ZEALOT_TOKEN','').strip()
    endpoint=args.endpoint or cfg.get('endpoint','https://apps.example.com')
    channel=args.channel_key or ''
    if channel.startswith('请'): channel=''
    build_started=time.time()
    if args.command=='release':
        command=cfg.get('build')
        if not isinstance(command,list) or not command or not all(isinstance(x,str) for x in command):
            raise ReleaseError('build 必须是非空命令数组，请配置项目实际构建命令')
        build_env=os.environ.copy()
        build_env.pop('ZEALOT_TOKEN',None)
        result=subprocess.run(command, env=build_env, stdout=sys.stderr, stderr=sys.stderr)
        if result.returncode: raise ReleaseError(f'构建失败，退出码 {result.returncode}，未上传')
    pattern=args.file or cfg.get('artifact')
    if not pattern: raise ReleaseError('请指定安装包路径或配置 artifact')
    artifacts=[Path(p) for p in glob.glob(pattern,recursive=True) if Path(p).is_file()]
    if len(artifacts)!=1: raise ReleaseError(f'产物路径应匹配且只匹配一个文件，目前为 {len(artifacts)} 个；请明确路径')
    artifact=artifacts[0]
    if args.command=='release' and artifact.stat().st_mtime < build_started-2:
        raise ReleaseError('构建命令结束后产物未更新，可能匹配到旧包；请检查 artifact 路径')
    fields={'channel_key':channel,'source':'team-cli',
            'changelog':args.changelog or git(['log','-10','--pretty=format:%s']),
            'ci_url':os.environ.get('CI_JOB_URL') or (os.environ.get('GITHUB_SERVER_URL','https://github.com')+'/'+os.environ['GITHUB_REPOSITORY']+'/actions/runs/'+os.environ['GITHUB_RUN_ID'] if os.environ.get('GITHUB_RUN_ID') else ''),
            'allow_duplicate':'true' if args.allow_duplicate else 'false'}
    result=upload(endpoint,token,artifact,fields)
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':
    try: run()
    except (ReleaseError,ValueError,FileNotFoundError) as error:
        print(json.dumps({'error':str(error)},ensure_ascii=False),file=sys.stderr)
        raise SystemExit(1)
