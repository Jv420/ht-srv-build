'use strict';

const body = document.body;
const vehicles = document.getElementById('vehicles');

async function post(action, model) {
  const response = await fetch(`https://${GetParentResourceName()}/action`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ action, model })
  });
  return response.json();
}

function money(value) {
  return new Intl.NumberFormat('nl-NL', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(Number(value || 0));
}

function render(items) {
  vehicles.innerHTML = '';
  for (const item of items) {
    const card = document.createElement('article');
    card.className = 'card';
    card.innerHTML = `
      <h3>${item.label}</h3>
      <p>Model: ${item.model}</p>
      <div class="row"><span>Verkoopprijs</span><span class="price">${money(item.price)}</span></div>
      <div class="actions">
        <button data-action="test">Proefrit</button>
        <button class="primary" data-action="buy">Kopen</button>
      </div>
    `;
    card.querySelector('[data-action="test"]').onclick = () => post('test', item.model);
    card.querySelector('[data-action="buy"]').onclick = () => {
      if (window.confirm(`${item.label} kopen voor ${money(item.price)}?`)) post('buy', item.model);
    };
    vehicles.appendChild(card);
  }
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type === 'open') {
    render(Array.isArray(data.vehicles) ? data.vehicles : []);
    body.classList.add('visible');
  } else if (data.type === 'close') {
    body.classList.remove('visible');
  }
});

document.getElementById('close').onclick = () => post('close', '');
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') post('close', '');
});
