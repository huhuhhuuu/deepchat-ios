// GitHub OAuth Device Flow 登录（无需安装 git / gh，只用 HTTPS API）
// 用法: node scripts/gh-device-login.js <token输出路径>
const https = require('https');
const fs = require('fs');
const path = require('path');

const CLIENT_ID = '178c6fc778ccc68e1d6a'; // GitHub CLI 的公开 OAuth App
const SCOPES = 'repo workflow read:org';
const OUT = process.argv[2] || path.join(__dirname, '..', '.ci-tools', 'token.txt');

function post(host, pathname, form, headers) {
  return new Promise((resolve, reject) => {
    const body = new URLSearchParams(form).toString();
    const req = https.request({
      host, path: pathname, method: 'POST', timeout: 30000,
      headers: Object.assign({
        'accept': 'application/json',
        'content-type': 'application/x-www-form-urlencoded',
        'content-length': Buffer.byteLength(body),
        'user-agent': 'deepchat-ci/1.0'
      }, headers || {})
    }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); } catch (e) { reject(new Error('bad json: ' + data.slice(0, 200))); }
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  let start;
  try {
    start = await post('github.com', '/login/device/code', { client_id: CLIENT_ID, scope: SCOPES });
  } catch (e) {
    console.error('DEVICE_CODE_FAILED ' + e.message);
    process.exit(1);
  }

  if (!start || !start.device_code) {
    console.error('DEVICE_CODE_FAILED ' + JSON.stringify(start).slice(0, 300));
    process.exit(1);
  }

  console.log('USER_CODE=' + start.user_code);
  console.log('VERIFY_URL=' + (start.verification_uri || 'https://github.com/login/device'));
  console.log('EXPIRES_IN=' + start.expires_in + 's');
  console.log('WAITING_FOR_AUTHORIZATION');

  let interval = Math.max(5, start.interval || 5) * 1000;
  const deadline = Date.now() + (start.expires_in || 900) * 1000;

  while (Date.now() < deadline) {
    await sleep(interval);
    let res;
    try {
      res = await post('github.com', '/login/oauth/access_token', {
        client_id: CLIENT_ID,
        device_code: start.device_code,
        grant_type: 'urn:ietf:params:oauth:grant-type:device_code'
      });
    } catch (e) {
      console.log('poll error: ' + e.message);
      continue;
    }

    if (res.access_token) {
      fs.mkdirSync(path.dirname(OUT), { recursive: true });
      fs.writeFileSync(OUT, res.access_token.trim(), 'utf8');
      console.log('AUTHORIZED token saved to ' + OUT);
      process.exit(0);
    }
    if (res.error === 'authorization_pending') continue;
    if (res.error === 'slow_down') { interval += 5000; continue; }
    if (res.error === 'expired_token') { console.error('EXPIRED 授权码已过期，请重新运行'); process.exit(2); }
    if (res.error === 'access_denied') { console.error('DENIED 用户取消了授权'); process.exit(3); }
    console.log('poll: ' + (res.error || 'unknown'));
  }

  console.error('EXPIRED 等待超时');
  process.exit(2);
})();
