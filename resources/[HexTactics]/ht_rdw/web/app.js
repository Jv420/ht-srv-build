'use strict';

const body = document.body;
const vehicle = document.getElementById('vehicle');
const fines = document.getElementById('fines');
let hasVehicle = false;
let currentData = {};

async function post(action, extra = {}) {
  const response = await fetch(`https://${GetParentResourceName()}/action`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ action, ...extra })
  });
  return response.json();
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;'
  })[character]);
}

function money(value) {
  return new Intl.NumberFormat('nl-NL', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(Number(value || 0));
}

function date(value) {
  if (!value) return 'Niet geldig';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? String(value) : parsed.toLocaleDateString('nl-NL');
}

function render(data) {
  currentData = data || {};
  const registry = currentData.registry;
  if (!hasVehicle) {
    vehicle.innerHTML = '<h3>Geen voertuig</h3><p>Je kunt wel je openstaande boetes bekijken en betalen.</p>';
  } else if (!registry) {
    vehicle.innerHTML = '<h3>Niet geregistreerd</h3><p>Dit voertuig staat niet in het RDW-register.</p>';
  } else {
    vehicle.innerHTML = `
      <h3>${escapeHtml(registry.plate)}</h3>
      <p>VIN: ${escapeHtml(registry.vin)}<br>Eigenaar: ${escapeHtml(registry.registered_name || 'Onbekend')}<br>
      APK geldig tot: ${date(registry.apk_expires_at)}<br>
      Verzekerd tot: ${date(registry.insurance_expires_at)}</p>
      <span class="badge">${Number(registry.apk_valid) === 1 ? 'APK geldig' : 'APK verlopen'}</span>
      <span class="badge">${Number(registry.insurance_valid) === 1 ? 'Verzekerd' : 'Niet verzekerd'}</span>
    `;
  }

  for (const button of document.querySelectorAll('#vehicleActions button')) button.disabled = !hasVehicle;
  document.getElementById('register').style.display = currentData.isStaff ? 'inline-flex' : 'none';
  document.getElementById('apk').style.display = currentData.isStaff ? 'inline-flex' : 'none';

  const rows = Array.isArray(currentData.fines) ? currentData.fines : [];
  fines.innerHTML = '';
  if (!rows.length) {
    fines.innerHTML = '<div class="empty">Geen openstaande boetes.</div>';
    return;
  }

  for (const fine of rows) {
    const card = document.createElement('article');
    card.className = 'card';
    card.innerHTML = `
      <h3>${escapeHtml(fine.fine_type)}</h3>
      <p>${escapeHtml(fine.plate)} • ${date(fine.issued_at)}</p>
      <div class="row"><span>Te betalen</span><span class="price">${money(fine.amount)}</span></div>
      <div class="actions"><button class="primary">Betalen</button></div>
    `;
    card.querySelector('button').onclick = () => post('payFine', { fineId: fine.id });
    fines.appendChild(card);
  }
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type === 'open') {
    hasVehicle = Boolean(data.hasVehicle);
    body.classList.add('visible');
    render({});
  } else if (data.type === 'data') {
    render(data.data || {});
  } else if (data.type === 'close') {
    body.classList.remove('visible');
  }
});

document.getElementById('close').onclick = () => post('close');
document.getElementById('inspect').onclick = () => post('inspect');
document.getElementById('apk').onclick = () => post('apk');
document.getElementById('insurance').onclick = () => post('insurance');
document.getElementById('register').onclick = () => {
  const targetId = window.prompt('Server-ID van de nieuwe eigenaar:');
  if (targetId) post('register', { targetId });
};
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') post('close');
});
