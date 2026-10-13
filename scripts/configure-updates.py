"""把版本号与 Sparkle 公开配置写入已组装的 App Bundle（只读公钥，不接触私钥）。"""
import base64
import json
import plistlib
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
config = json.loads((root / 'Updates/config.json').read_text())
p = Path(sys.argv[1]) / 'Contents/Info.plist'
info = plistlib.loads(p.read_bytes())
info.update(CFBundleShortVersionString=config['version'], CFBundleVersion=config['build'],
            LSMinimumSystemVersion=config['minimumSystemVersion'])
key = config['publicKey']
if key and len(base64.b64decode(key, validate=True)) == 32:
    info.update(SUFeedURL=config['feedURL'], SUPublicEDKey=key,
                SUEnableAutomaticChecks=True, SUScheduledCheckInterval=86400,
                SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
                SUEnableSystemProfiling=False, SUVerifyUpdateBeforeExtraction=True)
elif '--require-key' in sys.argv:
    raise SystemExit('未配置 Sparkle 公钥，见 Updates/README.md。')
else:
    print('⚠️  未配置 Sparkle 公钥，本次构建不含检查更新功能（见 Updates/README.md）。')
p.write_bytes(plistlib.dumps(info))
