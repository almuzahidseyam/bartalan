// Real server integration test. Requires Node >=22 and the private bootstrap credentials.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { randomBytes, createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
const base = (process.env.BARTALAN_TEST_URL || 'http://localhost:8065').replace(/\/$/, '');
const credentials = JSON.parse(await readFile(resolve(root, '.secrets/admin.json'), 'utf8'));
const results = [];
const users = [];
const tokens = [];
const posts = [];
const attachments = [];
let adminToken, team, socket;
const report = (name) => { results.push({ name, passed: true }); console.log(`PASS ${name}`); };

async function api(path, { method = 'GET', token, body, raw = false, expected } = {}) {
  const headers = token ? { Authorization: `Bearer ${token}` } : {};
  if (body && !(body instanceof FormData)) headers['Content-Type'] = 'application/json';
  const response = await fetch(`${base}/api/v4${path}`, {
    method, headers, body: body instanceof FormData ? body : body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(20000),
  });
  if (expected) { assert.equal(response.status, expected); return response; }
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status} ${await response.text()}`);
  if (raw) return response;
  return response.json();
}

async function login(username, password) {
  const response = await api('/users/login', { method: 'POST', body: {login_id: username, password}, raw: true });
  const token = response.headers.get('token');
  assert.ok(token, 'Login must return a session token');
  tokens.push(token);
  return {user: await response.json(), token};
}

try {
  assert.equal((await api('/system/ping')).status, 'OK');
  report('server health');
  const html = await fetch(base).then(r => r.text());
  assert.match(html, /<html/i);
  report('web client served locally');
  ({token: adminToken} = await login(credentials.username, credentials.password));
  const config = await api('/config', {token: adminToken});
  assert.equal(config.LogSettings.EnableDiagnostics, false);
  assert.equal(config.EmailSettings.SendPushNotifications, false);
  assert.equal(config.EmailSettings.SendEmailNotifications, false);
  assert.equal(config.ServiceSettings.EnableLinkPreviews, false);
  assert.equal(config.PluginSettings.Enable, false);
  assert.equal(config.TeamSettings.EnableOpenServer, false);
  report('offline settings and closed public registration');

  const suffix = randomBytes(5).toString('hex');
  const registration = await fetch(`${base}/api/v4/users`, {method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({username:`outsider-${suffix}`,email:`outsider-${suffix}@bartalan.invalid`,password:randomBytes(24).toString('hex')})});
  if(registration.ok) {users.push(await registration.json());throw new Error('Uninvited registration unexpectedly allowed');}
  assert.ok([400,401,403].includes(registration.status));
  report('uninvited account registration rejected');
  team = await api('/teams', {method: 'POST', token: adminToken,
    body: {name: `verify-${suffix}`, display_name: 'BartaLAN verification', type: 'I'}});
  for (const role of ['sender', 'receiver']) {
    const username = `${role}-${suffix}`;
    const password = randomBytes(24).toString('hex');
    const user = await api('/users', {method:'POST', token:adminToken,
      body:{username, email:`${username}@bartalan.invalid`, password}});
    users.push(user);
    await api(`/teams/${team.id}/members`, {method:'POST', token:adminToken, body:{team_id:team.id, user_id:user.id}});
    Object.assign(user, await login(username,password));
  }
  report('two independent local account logins');
  const [sender, receiver] = users;
  const channel = await api('/channels', {method:'POST', token:adminToken,
    body:{team_id:team.id, name:`test-${suffix}`, display_name:'Verification', type:'O'}});
  for (const user of users) await api(`/channels/${channel.id}/members`, {
    method:'POST',token:adminToken,body:{user_id:user.id}});

  const events = [];
  socket = new WebSocket(`${base.replace(/^http/, 'ws')}/api/v4/websocket`);
  socket.addEventListener('message', event => events.push(JSON.parse(event.data)));
  await new Promise((resolve,reject) => {
    const timer = setTimeout(() => reject(new Error('WebSocket connection timed out')),10000);
    socket.addEventListener('open',()=>{clearTimeout(timer);resolve();},{once:true});
    socket.addEventListener('error',()=>{clearTimeout(timer);reject(new Error('WebSocket failed'));},{once:true});
  });
  socket.send(JSON.stringify({seq:1,action:'authentication_challenge',data:{token:receiver.token}}));
  async function waitFor(predicate) {
    for (let i=0;i<100;i++) { const event=events.find(predicate); if(event) return event; await new Promise(r=>setTimeout(r,100)); }
    throw new Error('Expected WebSocket event did not arrive');
  }
  await waitFor(e=>e.seq_reply===1 && e.status==='OK');
  report('authenticated live WebSocket connection');
  const message='ইন্টারনেট ছাড়াই বার্তা, ছবি ও ফাইল — BartaLAN 🇧🇩';
  const post = await api('/posts',{method:'POST',token:sender.token,body:{channel_id:channel.id,message}});
  posts.push(post.id);
  const event = await waitFor(e=>e.event==='posted' && JSON.parse(e.data.post).id===post.id);
  assert.equal(JSON.parse(event.data.post).message,message);
  assert.equal((await api(`/posts/${post.id}`,{token:receiver.token})).message,message);
  report('Bengali text delivered live to a second account');

  const dm = await api('/channels/direct',{method:'POST',token:sender.token,body:[sender.id,receiver.id]});
  const directPost=await api('/posts',{method:'POST',token:sender.token,body:{channel_id:dm.id,message:'Private local message'}});
  posts.push(directPost.id);
  assert.equal((await api(`/posts/${directPost.id}`,{token:receiver.token})).message,'Private local message');
  report('direct message delivery');

  const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jv0kAAAAASUVORK5CYII=','base64');
  for (const [name,bytes,mime] of [['photo.png',png,'image/png'],['sample.bin',randomBytes(131072),'application/octet-stream']]) {
    const form=new FormData(); form.set('channel_id',channel.id); form.set('files',new Blob([bytes],{type:mime}),name);
    const upload=await api('/files',{method:'POST',token:sender.token,body:form});
    const id=upload.file_infos[0].id;
    const attachment=await api('/posts',{method:'POST',token:sender.token,body:{channel_id:channel.id,message:`Attachment: ${name}`,file_ids:[id]}});
    posts.push(attachment.id);
    const downloaded=Buffer.from(await (await api(`/files/${id}`,{token:receiver.token,raw:true})).arrayBuffer());
    const hash=b=>createHash('sha256').update(b).digest('hex');
    assert.equal(hash(downloaded),hash(bytes));
    attachments.push({id,bytes});
    const unauth=await fetch(`${base}/api/v4/files/${id}`);
    assert.ok([401,403].includes(unauth.status),'Files must require authentication');
    report(`${name}: upload, second-user download, matching SHA-256, access control`);
  }
  if(process.argv.includes('--restart')) {
    const linuxRoot=root.replace(/^([A-Za-z]):/,(_,drive)=>`/mnt/${drive.toLowerCase()}`).replaceAll('\\','/');
    function compose(args) {
      const command=process.platform==='win32'?'wsl.exe':'docker';
      const prefix=process.platform==='win32'?['-d','BartaLAN','-u','root','--exec','docker','compose','--project-directory',linuxRoot]:['compose','--project-directory',root];
      const result=spawnSync(command,[...prefix,...args],{encoding:'utf8',timeout:240000});
      assert.equal(result.status,0,`Server restart command failed: ${result.stderr || result.error || ''}`);
    }
    compose(['stop']);
    compose(['up','-d','--pull','never','--wait','--wait-timeout','180']);
    for(let i=0;i<90;i++) {
      try {if((await api('/system/ping')).status==='OK') break;}catch{}
      await new Promise(resolve=>setTimeout(resolve,1000));
    }
    assert.equal((await api(`/posts/${post.id}`,{token:receiver.token})).message,message);
    for(const {id,bytes} of attachments) {
      const downloaded=Buffer.from(await (await api(`/files/${id}`,{token:receiver.token,raw:true})).arrayBuffer());
      assert.deepEqual(downloaded,bytes);
    }
    report('accounts, messages, photo, and file persist after stopping and starting both services');
  }
} catch(error) {
  results.push({name:error.message,passed:false}); console.error(`FAIL ${error.message}`); process.exitCode=1;
} finally {
  socket?.close();
  for(const id of posts) await api(`/posts/${id}`,{method:'DELETE',token:adminToken}).catch(()=>{});
  for(const user of users) await api(`/users/${user.id}/active`,{method:'PUT',token:adminToken,body:{active:false}}).catch(()=>{});
  if(team) await api(`/teams/${team.id}`,{method:'DELETE',token:adminToken}).catch(()=>{});
  for(const token of tokens) await api('/users/logout',{method:'POST',token}).catch(()=>{});
  await mkdir(resolve(root,'reports'),{recursive:true});
  await writeFile(resolve(root,'reports/local-smoke.json'),JSON.stringify({tested_at:new Date().toISOString(),base,results},null,2)+'\n');
}
