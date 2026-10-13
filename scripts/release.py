#!/usr/bin/env python3
"""准备 Sparkle 更新发布；只有加 --publish 才会创建 GitHub Release 并更新线上 appcast。"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
FEED_PATH = 'appcast.xml'
EMPTY_FEED = b'<?xml version="1.0" encoding="utf-8"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>RemoteMate</title></channel></rss>\n'


def run(*args, capture=False):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def api(path, payload=None):
    method = ['--method', 'PUT' if '/contents/' in path else 'POST', '--input', '-'] if payload else []
    result = subprocess.run(['gh', 'api', path] + method, input=json.dumps(payload) if payload else None,
                            text=True, capture_output=True, cwd=ROOT)
    if result.returncode:
        if payload is None and '(HTTP 404)' in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


def find_release(repo, tag):
    # by-tag 接口只返回已公开的 Release，草稿需要遍历列表，否则重试会创建重复草稿。
    published = api(f'repos/{repo}/releases/tags/{tag}')
    if published is not None:
        return published
    page = 1
    while True:
        releases = api(f'repos/{repo}/releases?per_page=100&page={page}')
        matches = [r for r in releases if r['tag_name'] == tag]
        if len(matches) > 1:
            raise RuntimeError('同一标签存在多个草稿 Release，请先手动清理。')
        if matches:
            return matches[0]
        if len(releases) < 100:
            return None
        page += 1


def read_feed(config):
    result = api(f"repos/{config['repository']}/contents/{FEED_PATH}?ref={config['feedBranch']}")
    return (base64.b64decode(result['content']), result['sha']) if result else (EMPTY_FEED, None)


def validate_feed(data, config, archive=None):
    """不带 archive 时返回线上最大构建号；带 archive 时校验本次条目与签名。"""
    items = ET.fromstring(data).findall('./channel/item')
    if archive is None:
        return max((int(i.findtext(SPARKLE + 'version', '0')) for i in items), default=0)
    matching = [i for i in items if i.findtext(SPARKLE + 'version') == config['build']]
    if len(matching) != 1:
        raise RuntimeError('appcast 中本次构建号的条目必须恰好一个。')
    item = matching[0]
    enclosure = item.find('enclosure')
    expected_url = f"https://github.com/{config['repository']}/releases/download/v{config['version']}/{archive.name}"
    if (item.findtext(SPARKLE + 'shortVersionString') != config['version']
            or enclosure is None or enclosure.get('url') != expected_url
            or enclosure.get('length') != str(archive.stat().st_size)):
        raise RuntimeError('appcast 的版本号、下载地址或文件大小与安装包不一致。')
    run(BIN / 'sign_update', '--account', config['keychainAccount'], '--verify',
        archive, enclosure.get(SPARKLE + 'edSignature', ''))


def init_feed(config):
    if read_feed(config)[1]:
        return
    repo = config['repository']
    if api(f"repos/{repo}/git/ref/heads/{config['feedBranch']}") is None:
        head = api(f'repos/{repo}/git/ref/heads/main')['object']['sha']
        api(f'repos/{repo}/git/refs', {'ref': f"refs/heads/{config['feedBranch']}", 'sha': head})
    api(f'repos/{repo}/contents/{FEED_PATH}', {
        'branch': config['feedBranch'], 'message': 'chore: initialize update feed',
        'content': base64.b64encode(EMPTY_FEED).decode()})


def publish(config, stage, head):
    if run('git', 'status', '--porcelain', capture=True) or run('git', 'rev-parse', 'HEAD', capture=True) != head:
        raise RuntimeError('准备期间源码有变动，请重新准备。')
    manifest = json.loads((stage / 'manifest.json').read_text())
    archive = stage / manifest['archive']
    feed = (stage / 'appcast.xml').read_bytes()
    if manifest['head'] != head or manifest['dirty'] or manifest['config'] != config:
        raise RuntimeError('已准备的产物必须对应当前干净提交和配置。')
    for name, digest in manifest['sha256'].items():
        if hashlib.sha256((stage / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError(f'已准备的文件被改动：{name}')
    validate_feed(feed, config, archive)
    live, sha = read_feed(config)
    if live == feed:
        print('该版本已发布。')
        return
    if validate_feed(live, config) >= int(config['build']):
        raise RuntimeError('线上 appcast 已包含相同或更新的构建号，拒绝回退。')
    repo, tag = config['repository'], f"v{config['version']}"
    if api(f'repos/{repo}/git/ref/tags/{tag}') is None:
        api(f'repos/{repo}/git/refs', {'ref': f'refs/tags/{tag}', 'sha': head})
    if api(f'repos/{repo}/commits/{tag}')['sha'] != head:
        raise RuntimeError('已有同名标签指向其他提交。')
    release = find_release(repo, tag)
    if release is None:
        run('gh', 'release', 'create', tag, '--repo', repo, '--target', head, '--draft',
            '--title', f"RemoteMate v{config['version']} · 远程伴侣", '--notes-file', stage / 'notes.md')
        release = find_release(repo, tag)
    assets = (archive.name, 'SHA256SUMS.txt')
    for name in assets:
        asset = next((a for a in release['assets'] if a['name'] == name), None)
        if asset and asset.get('digest') != 'sha256:' + manifest['sha256'][name]:
            raise RuntimeError(f'远端资产内容不同，拒绝覆盖：{name}')
        if not asset:
            if not release['draft']:
                raise RuntimeError('已公开的 Release 缺少预期资产。')
            run('gh', 'release', 'upload', tag, stage / name, '--repo', repo)
    release = find_release(repo, tag)
    for name in assets:
        asset = next(a for a in release['assets'] if a['name'] == name)
        if asset.get('digest') != 'sha256:' + manifest['sha256'][name]:
            raise RuntimeError('远端资产校验和不一致。')
    if release['draft']:
        run('gh', 'release', 'edit', tag, '--repo', repo, '--draft=false', '--latest')
    # 资产公开后才推送 appcast；contents SHA 防止并发覆盖。
    payload = {'branch': config['feedBranch'], 'message': f'chore: publish {tag} update feed',
               'content': base64.b64encode(feed).decode()}
    if sha:
        payload['sha'] = sha
    api(f'repos/{repo}/contents/{FEED_PATH}', payload)
    if read_feed(config)[0] != feed:
        raise RuntimeError('线上 appcast 校验失败。')
    print(f'已发布：https://github.com/{repo}/releases/tag/{tag}')


def prepare(config, stage, head, dirty):
    live, _ = read_feed(config)
    if validate_feed(live, config) >= int(config['build']):
        raise RuntimeError('请先递增 Updates/config.json 中的 version 和 build。')
    notes = ROOT / f"Updates/{config['version']}.md"
    if not notes.is_file():
        raise RuntimeError(f'请先编写更新说明：{notes}')
    if run(BIN / 'generate_keys', '--account', config['keychainAccount'], '-p', capture=True) != config['publicKey']:
        raise RuntimeError('钥匙串中的 Sparkle 公钥与 config.json 不一致。')
    run('swift', 'test', '--scratch-path', Path(tempfile.gettempdir()) / 'remotemate-test-build')
    run(ROOT / 'build.sh', '--require-key')
    run(ROOT / 'scripts/build-dmg.sh', config['version'])
    out = ROOT / f"build/releases/{config['version']}"
    archive = out / f"RemoteMate-{config['version']}-macOS-arm64.dmg"
    with tempfile.TemporaryDirectory(prefix='remotemate-release-') as temporary:
        work = Path(temporary)
        shutil.copy2(archive, work / archive.name)
        shutil.copy2(out / 'SHA256SUMS.txt', work / 'SHA256SUMS.txt')
        shutil.copy2(notes, work / (archive.stem + '.md'))  # generate_appcast 按同名 .md 嵌入更新说明
        shutil.copy2(notes, work / 'notes.md')
        if ET.fromstring(live).findall('./channel/item'):
            (work / 'appcast.xml').write_bytes(live)
        prefix = f"https://github.com/{config['repository']}/releases/download/v{config['version']}/"
        run(BIN / 'generate_appcast', '--account', config['keychainAccount'],
            '--download-url-prefix', prefix, '--maximum-deltas', '0', '--embed-release-notes', work)
        validate_feed((work / 'appcast.xml').read_bytes(), config, work / archive.name)
        hashes = {name: hashlib.sha256((work / name).read_bytes()).hexdigest()
                  for name in (archive.name, 'SHA256SUMS.txt', 'appcast.xml', 'notes.md')}
        (work / 'manifest.json').write_text(json.dumps(dict(head=head, dirty=dirty, config=config,
            archive=archive.name, sha256=hashes), indent=2, ensure_ascii=False) + '\n')
        stage.mkdir(parents=True, exist_ok=True)
        for file in work.iterdir():
            if file.is_file():
                shutil.copy2(file, stage / file.name)
    print(f'已准备，可审核：{stage}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true', help='准备后创建 Release、上传安装包并发布 appcast')
    parser.add_argument('--resume', action='store_true', help='发布已准备且未改动的产物（中断后继续）')
    parser.add_argument('--init-feed', action='store_true', help='仅创建空的线上 appcast')
    args = parser.parse_args()
    config = json.loads((ROOT / 'Updates/config.json').read_text())
    if not re.fullmatch(r'\d+\.\d+\.\d+', config['version']) or not re.fullmatch(r'[1-9]\d*', config['build']):
        raise RuntimeError('version 需为 x.y.z，build 需为正整数。')
    if args.init_feed:
        init_feed(config)
        print(config['feedURL'])
        return
    if args.resume and not args.publish:
        parser.error('--resume 需要与 --publish 一起使用')
    head = run('git', 'rev-parse', 'HEAD', capture=True)
    dirty = bool(run('git', 'status', '--porcelain', capture=True))
    if args.publish:
        remote = api(f"repos/{config['repository']}/git/ref/heads/main")
        if dirty or remote['object']['sha'] != head:
            raise RuntimeError('发布前请先提交并推送到 main。')
        init_feed(config)
    stage = ROOT / f"build/releases/{config['version']}/sparkle"
    if not args.resume:
        prepare(config, stage, head, dirty)
    if args.publish:
        publish(config, stage, head)


if __name__ == '__main__':
    main()
