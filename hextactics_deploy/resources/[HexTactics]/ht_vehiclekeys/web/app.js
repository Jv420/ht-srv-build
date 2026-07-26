'use strict';

const body = document.body;
const content = document.getElementById('content');
const title = document.getElementById('title');
const subtitle = document.getElementById('subtitle');

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;'
  })[character]);
}

async function post(action, extra = {}) {
  const response = await fetch(`https://${GetParentResourceName()}/action`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ action, ...extra })
  });
  return response.json();
}

function render(keys) {
  content.innerHTML = '';
  if (!keys.length) {
    content.innerHTML = '<div class="empty">Je hebt nog geen voertuigsleutels.</div>';
    return;
  }

  for (const key of keys) {
    const card = document.createElement('article');
    card.className = 'card';
    const tracker = Number(key.tracker_enabled) === 1;
    card.innerHTML = `
      <h3>${escapeHtml(key.plate)}</h3>
      <p>${escapeHtml(key.vehicle_model || 'Onbekend voertuig')}</p>
      <span class="badge">${key.key_type === 'owner' ? 'Eigenaarsleutel' : 'Gedeelde sleutel'}</span>
      <span class="badge">${tracker ? 'Tracker actief' : 'Geen tracker'}</span>
      <div class="actions">
        <button class="primary" data-action="toggle">Open / sluit</button>
        <button data-action="track" ${tracker ? '' : 'disabled'}>Zoek voertuig</button>
        ${key.key_type === 'owner' ? '<button data-action="give">Sleutel delen</button>' : ''}
      </div>
    `;

    card.querySelector('[data-action="toggle"]').onclick = () => post('toggle', { plate: key.plate });
    const track = card.querySelector('[data-action="track"]');
    if (track) track.onclick = () => post('track', { plate: key.plate });

    const give = card.querySelector('[data-action="give"]');
    if (give) {
      give.onclick = () => {
        const targetId = window.prompt('Server-ID van de ontvanger:');
        if (targetId) post('give', { plate: key.plate, targetId });
      };
    }

    content.appendChild(card);
  }
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type === 'open') {
    title.textContent = data.title || 'Voertuigsleutels';
    subtitle.textContent = data.subtitle || '';
    render(Array.isArray(data.keys) ? data.keys : []);
    body.classList.add('visible');
  } else if (data.type === 'close') {
    body.classList.remove('visible');
  }
});

document.getElementById('close').onclick = () => post('close');
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') post('close');
});
