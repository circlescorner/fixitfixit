/* ── Sandbox Dashboard JS ── */

const API = '';

// ── Toast ──
function toast(msg, type = 'success') {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.className = 'toast ' + type;
  setTimeout(() => el.classList.add('hidden'), 3500);
}

// ── Fetch helpers ──
async function api(path, opts = {}) {
  try {
    const res = await fetch(API + path, {
      headers: { 'Content-Type': 'application/json' },
      ...opts,
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (e) {
    toast('Error: ' + e.message, 'error');
    throw e;
  }
}

// ── Containers ──
async function loadContainers() {
  const containers = await api('/api/containers');
  const grid = document.getElementById('containers');
  const logSelect = document.getElementById('log-container');

  if (!containers.length) {
    grid.innerHTML = '<div class="loading">No sandbox containers running. Click "Start All" to spin them up.</div>';
    return;
  }

  grid.innerHTML = containers.map(c => `
    <div class="card">
      <h3>${c.name}</h3>
      <div class="meta">
        <span class="status status-${c.status}">${c.status}</span>
        <span>IP: <code>${c.ip || '—'}</code></span>
      </div>
      <div class="meta">
        <span>Image: <code>${c.image}</code></span>
      </div>
      <div class="actions">
        ${c.status === 'running'
          ? `<button class="btn btn-sm btn-muted" onclick="containerAction('${c.name}','restart')">Restart</button>
             <button class="btn btn-sm btn-red" onclick="containerAction('${c.name}','stop')">Stop</button>`
          : `<button class="btn btn-sm btn-green" onclick="containerAction('${c.name}','start')">Start</button>`}
      </div>
    </div>
  `).join('');

  // Populate log dropdown
  logSelect.innerHTML = containers.map(c =>
    `<option value="${c.name}">${c.name}</option>`
  ).join('');
}

async function containerAction(name, action) {
  await api(`/api/containers/${name}/${action}`, { method: 'POST' });
  toast(`${name}: ${action} OK`);
  loadContainers();
}

async function sandboxUp() {
  toast('Starting sandbox containers...');
  await api('/api/sandbox/up', { method: 'POST' });
  toast('Sandbox containers started');
  loadContainers();
}

async function sandboxDown() {
  if (!confirm('Stop all sandbox containers?')) return;
  await api('/api/sandbox/down', { method: 'POST' });
  toast('Sandbox containers stopped');
  loadContainers();
}

// ── Networks ──
async function loadNetworks() {
  const nets = await api('/api/networks');
  const grid = document.getElementById('networks');

  if (!nets.length) {
    grid.innerHTML = '<div class="loading">No custom networks.</div>';
    return;
  }

  grid.innerHTML = nets.map(n => `
    <div class="card">
      <h3>${n.name}</h3>
      <div class="meta">
        <span>Driver: ${n.driver}</span>
        <span>Subnet: <code>${n.subnet || '—'}</code></span>
      </div>
      <div class="net-containers">
        ${n.containers.map(c => `<span class="net-tag">${c}</span>`).join('')}
      </div>
    </div>
  `).join('');
}

// ── Droplets ──
async function loadDroplets() {
  const droplets = await api('/api/droplets');
  const grid = document.getElementById('droplets');

  if (!droplets.length) {
    grid.innerHTML = '<div class="loading">No droplets. Click "+ New Droplet" to create one.</div>';
    return;
  }

  grid.innerHTML = droplets.map(d => `
    <div class="card">
      <h3>${d.name}</h3>
      <div class="meta">
        <span class="status status-${d.status}">${d.status}</span>
        <span>${d.size} / ${d.region}</span>
      </div>
      <div class="meta">
        <span>Public: <code>${d.public_ip || 'pending...'}</code></span>
        <span>VPC: <code>${d.private_ip || 'pending...'}</code></span>
      </div>
      <div class="actions">
        <button class="btn btn-sm btn-red" onclick="destroyDroplet(${d.id}, '${d.name}')">Destroy</button>
      </div>
    </div>
  `).join('');
}

function showNewDropletForm() {
  document.getElementById('new-droplet-form').classList.remove('hidden');
}
function hideNewDropletForm() {
  document.getElementById('new-droplet-form').classList.add('hidden');
}

async function createDroplet() {
  const name = document.getElementById('droplet-name').value.trim();
  const size = document.getElementById('droplet-size').value;
  if (!name) { toast('Enter a name', 'error'); return; }

  toast('Creating droplet...');
  await api('/api/droplets', {
    method: 'POST',
    body: JSON.stringify({ name, size }),
  });
  toast('Droplet created! It may need a minute to boot.');
  hideNewDropletForm();
  loadDroplets();
}

async function destroyDroplet(id, name) {
  if (!confirm(`Destroy droplet "${name}"? This cannot be undone.`)) return;
  await api(`/api/droplets/${id}`, { method: 'DELETE' });
  toast(`Droplet ${name} destroyed`);
  loadDroplets();
}

// ── Config ──
async function updateConfig() {
  const slot = document.getElementById('cfg-slot').value;
  const image = document.getElementById('cfg-image').value.trim();
  if (!image) { toast('Enter an image', 'error'); return; }

  await api('/api/sandbox/config', {
    method: 'PUT',
    body: JSON.stringify({ slot: parseInt(slot), image }),
  });
  toast(`Box ${slot} image updated to ${image}. Restarting...`);

  // Recreate to pick up new image
  await api('/api/sandbox/up', { method: 'POST' });
  loadContainers();
}

// ── Logs ──
async function fetchLogs() {
  const name = document.getElementById('log-container').value;
  if (!name) return;
  const data = await api(`/api/containers/${name}/logs?tail=200`);
  document.getElementById('log-output').textContent = data.logs || '(empty)';
}

// ── Init ──
document.addEventListener('DOMContentLoaded', () => {
  loadContainers();
  loadNetworks();
  loadDroplets();

  // Auto-refresh every 15s
  setInterval(() => {
    loadContainers();
    loadNetworks();
  }, 15000);

  // Refresh droplets every 30s
  setInterval(loadDroplets, 30000);
});
