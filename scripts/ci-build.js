// 用 GitHub API 完成：建仓库 → 上传工程 → 触发 macOS 编译 → 下载 IPA
// 用法: node scripts/ci-build.js <token文件> [仓库名]
const https = require('https');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const TOKEN_FILE = process.argv[2] || path.join(ROOT, '.ci-tools', 'token.txt');
const REPO_NAME = process.argv[3] || 'deepchat-ios';
const WORKFLOW = 'build-ipa.yml';
const BRANCH = 'main';

const TOKEN = fs.readFileSync(TOKEN_FILE, 'utf8').trim();

const SKIP_DIRS = new Set(['.ci-tools', 'dist', '.build', '.git', 'build', 'DerivedData', 'node_modules', '__pycache__']);
const SKIP_EXT = new Set(['.zip', '.ipa', '.xcarchive', '.jks', '.part']);

function api(method, pathname, body, host) {
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : null;
    const req = https.request({
      host: host || 'api.github.com',
      path: pathname,
      method,
      timeout: 60000,
      headers: Object.assign({
        'user-agent': 'deepchat-ci/1.0',
        'accept': 'application/vnd.github+json',
        'authorization': 'Bearer ' + TOKEN,
        'x-github-api-version': '2022-11-28'
      }, payload ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(payload) } : {})
    }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const raw = Buffer.concat(chunks);
        if (res.statusCode === 302 || res.statusCode === 301) {
          return resolve({ redirect: res.headers.location, status: res.statusCode });
        }
        let json = null;
        try { json = JSON.parse(raw.toString('utf8')); } catch (e) { /* 非 JSON */ }
        if (res.statusCode >= 400) {
          const msg = json && json.message ? json.message : raw.toString('utf8').slice(0, 300);
          return reject(new Error(method + ' ' + pathname + ' -> HTTP ' + res.statusCode + ': ' + msg));
        }
        resolve(json);
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout ' + pathname)));
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const headers = { 'user-agent': 'deepchat-ci/1.0', 'accept': 'application/vnd.github+json' };
    if (u.host === 'api.github.com') headers['authorization'] = 'Bearer ' + TOKEN;
    const req = https.request({
      host: u.host,
      path: u.pathname + u.search,
      method: 'GET',
      timeout: 120000,
      headers: headers
    }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        return resolve(download(res.headers.location, dest));
      }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error('download HTTP ' + res.statusCode)); }
      const out = fs.createWriteStream(dest);
      res.pipe(out);
      out.on('finish', () => out.close(() => resolve(dest)));
      out.on('error', reject);
    });
    req.on('timeout', () => req.destroy(new Error('download timeout')));
    req.on('error', reject);
    req.end();
  });
}

function collectFiles(dir, base, list) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    const rel = path.relative(base, full).replace(/\\/g, '/');
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name)) continue;
      collectFiles(full, base, list);
    } else {
      if (SKIP_EXT.has(path.extname(entry.name).toLowerCase())) continue;
      list.push(rel);
    }
  }
  return list;
}

/** 不加任何过滤地列出目录下所有文件（下载产物时用） */
function collectAll(dir, base, list) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    const rel = path.relative(base, full).replace(/\\/g, '/');
    if (entry.isDirectory()) collectAll(full, base, list);
    else list.push(rel);
  }
  return list;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  console.log('==> 校验身份');
  const me = await api('GET', '/user');
  console.log('    登录账号: ' + me.login);

  console.log('==> 创建/获取仓库 ' + me.login + '/' + REPO_NAME);
  let repo;
  try {
    repo = await api('POST', '/user/repos', {
      name: REPO_NAME,
      description: 'DeepChat · iOS 17 纯 API 聊天客户端（自动构建）',
      private: false,
      has_issues: false,
      has_wiki: false,
      has_projects: false,
      auto_init: false
    });
    console.log('    已创建: ' + repo.html_url);
  } catch (e) {
    try {
      repo = await api('GET', '/repos/' + me.login + '/' + REPO_NAME);
      console.log('    仓库已存在: ' + repo.html_url);
    } catch (e2) {
      throw new Error('无法创建或读取仓库: ' + e.message);
    }
  }

  console.log('==> 收集文件');
  const files = collectFiles(ROOT, ROOT, []);
  console.log('    共 ' + files.length + ' 个文件');

  // 空仓库无法直接创建 blob，先用 Contents API 落一个初始提交
  console.log('==> 初始化仓库分支');
  let baseSha = null;
  let branch = BRANCH;
  try {
    const ref = await api('GET', '/repos/' + me.login + '/' + REPO_NAME + '/git/ref/heads/' + branch);
    baseSha = ref.object.sha;
    console.log('    已存在分支 ' + branch);
  } catch (e) {
    if (!/empty|not found|409|404/i.test(e.message)) throw e;
    const repoInfo = await api('GET', '/repos/' + me.login + '/' + REPO_NAME);
    branch = repoInfo.default_branch || BRANCH;
    await api('PUT', '/repos/' + me.login + '/' + REPO_NAME + '/contents/.chatdock-init', {
      message: '初始化仓库',
      content: Buffer.from('DeepChat\n').toString('base64'),
      branch: branch
    });
    const ref = await api('GET', '/repos/' + me.login + '/' + REPO_NAME + '/git/ref/heads/' + branch);
    baseSha = ref.object.sha;
    console.log('    已初始化分支 ' + branch);
  }

  console.log('==> 上传文件内容（blobs）');
  const tree = [];
  for (const rel of files) {
    const content = fs.readFileSync(path.join(ROOT, rel));
    const blob = await api('POST', '/repos/' + me.login + '/' + REPO_NAME + '/git/blobs', {
      content: content.toString('base64'),
      encoding: 'base64'
    });
    tree.push({ path: rel, mode: '100644', type: 'blob', sha: blob.sha });
    process.stdout.write('.');
  }
  console.log('\n    完成');

  console.log('==> 创建 tree / commit / branch');
  const treeRes = await api('POST', '/repos/' + me.login + '/' + REPO_NAME + '/git/trees', { tree });
  const commit = await api('POST', '/repos/' + me.login + '/' + REPO_NAME + '/git/commits', {
    message: 'DeepChat iOS 源码（自动推送）',
    tree: treeRes.sha,
    parents: baseSha ? [baseSha] : []
  });

  try {
    await api('POST', '/repos/' + me.login + '/' + REPO_NAME + '/git/refs', {
      ref: 'refs/heads/' + branch,
      sha: commit.sha
    });
  } catch (e) {
    await api('PATCH', '/repos/' + me.login + '/' + REPO_NAME + '/git/refs/heads/' + branch, { sha: commit.sha, force: true });
  }
  console.log('    commit ' + commit.sha.slice(0, 8) + ' @ ' + branch);

  console.log('==> 触发 GitHub Actions 编译');
  await api('POST', '/repos/' + me.login + '/' + REPO_NAME + '/actions/workflows/' + WORKFLOW + '/dispatches', { ref: branch });

  const startedAt = Date.now();
  let runId = null;
  for (let i = 0; i < 30; i++) {
    await sleep(4000);
    const runs = await api('GET', '/repos/' + me.login + '/' + REPO_NAME + '/actions/runs?branch=' + branch + '&per_page=5');
    const run = (runs.workflow_runs || []).find((r) => r.name && r.name.indexOf('unsigned') >= 0) || (runs.workflow_runs || [])[0];
    if (run) { runId = run.id; break; }
  }
  if (!runId) throw new Error('没有找到工作流运行记录');
  console.log('    run id: ' + runId + '  (' + Math.round((Date.now() - startedAt) / 1000) + 's)');

  let conclusion = null;
  for (let i = 0; i < 150; i++) {
    await sleep(6000);
    const run = await api('GET', '/repos/' + me.login + '/' + REPO_NAME + '/actions/runs/' + runId);
    process.stdout.write('\r    状态: ' + run.status + (run.conclusion ? ' / ' + run.conclusion : '') + '   ');
    if (run.status === 'completed') { conclusion = run.conclusion; break; }
  }
  console.log('');

  const runInfo = await api('GET', '/repos/' + me.login + '/' + REPO_NAME + '/actions/runs/' + runId);

  if (conclusion !== 'success') {
    console.log('==> 编译失败，抓取构建日志');
    try {
      const arts = await api('GET', '/repos/' + me.login + '/' + REPO_NAME + '/actions/runs/' + runId + '/artifacts');
      const logArt = (arts.artifacts || []).find((a) => a.name === 'build-log');
      if (!logArt) throw new Error('没有 build-log artifact');
      const zipPath = path.join(ROOT, '.ci-tools', 'build-log.zip');
      await download('https://api.github.com/repos/' + me.login + '/' + REPO_NAME + '/actions/artifacts/' + logArt.id + '/zip', zipPath);
      const dir = path.join(ROOT, '.ci-tools', 'build-log');
      fs.rmSync(dir, { recursive: true, force: true });
      fs.mkdirSync(dir, { recursive: true });
      execFileSync('tar.exe', ['-xf', zipPath, '-C', dir]);
      const logFile = collectFiles(dir, dir, []).find((f) => f.endsWith('.log'));
      if (!logFile) throw new Error('日志文件不存在');
      const text = fs.readFileSync(path.join(dir, logFile), 'utf8');
      fs.writeFileSync(path.join(ROOT, '.ci-tools', 'build-log.txt'), text);
      const lines = text.split('\n');
      const errs = lines.filter((l) => /error:|fatal error:|\*\* BUILD FAILED|xcodebuild: error|The following build commands failed/i.test(l));
      console.log('---- 关键错误（共 ' + errs.length + ' 行）----');
      console.log(errs.slice(0, 50).join('\n') || text.slice(-3000));
    } catch (e) {
      console.log('    日志获取失败: ' + e.message);
    }
    console.log('    运行地址: ' + runInfo.html_url);
    process.exit(1);
  }

  console.log('==> 下载构建产物');
  const arts = await api('GET', '/repos/' + me.login + '/' + REPO_NAME + '/actions/runs/' + runId + '/artifacts');
  const artifact = (arts.artifacts || []).find((a) => a.name.indexOf('ipa') >= 0);
  if (!artifact) throw new Error('没有找到 IPA artifact');

  const zipPath = path.join(ROOT, '.ci-tools', 'artifact.zip');
  await download('https://api.github.com/repos/' + me.login + '/' + REPO_NAME + '/actions/artifacts/' + artifact.id + '/zip', zipPath);
  console.log('    已下载 ' + (fs.statSync(zipPath).size / 1024).toFixed(0) + ' KB');

  const outDir = path.join(ROOT, 'dist');
  fs.mkdirSync(outDir, { recursive: true });
  const extractDir = path.join(ROOT, '.ci-tools', 'artifact');
  fs.rmSync(extractDir, { recursive: true, force: true });
  fs.mkdirSync(extractDir, { recursive: true });
  execFileSync('tar.exe', ['-xf', zipPath, '-C', extractDir]);

  const ipa = collectAll(extractDir, extractDir, []).find((f) => f.toLowerCase().endsWith('.ipa'));
  if (!ipa) throw new Error('解压后没有找到 .ipa');
  const finalPath = path.join(outDir, path.basename(ipa));
  fs.copyFileSync(path.join(extractDir, ipa), finalPath);
  const size = (fs.statSync(finalPath).size / 1024 / 1024).toFixed(1);
  console.log('');
  console.log('IPA_PATH=' + finalPath);
  console.log('IPA_SIZE=' + size + 'MB');
  console.log('RUN_URL=' + runInfo.html_url);
})().catch((e) => {
  console.error('FAILED: ' + e.message);
  process.exit(1);
});
