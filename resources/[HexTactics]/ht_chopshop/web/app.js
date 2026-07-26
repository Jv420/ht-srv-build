'use strict';

const body = document.body;
const subtitle = document.getElementById('subtitle');

async function post(action) {
  const response = await fetch(`https://${GetParentResourceName()}/action`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ action })
  });
  return response.json();
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type === 'open') {
    const amount = new Intl.NumberFormat('nl-NL', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(Number(data.price || 0));
    subtitle.textContent = `${data.plate || 'Onbekend'} • omkatkosten ${amount}`;
    body.classList.add('visible');
  } else if (data.type === 'close') {
    body.classList.remove('visible');
  }
});

document.getElementById('close').onclick = () => post('close');
document.getElementById('reidentity').onclick = () => post('reidentity');
document.getElementById('trackerAdd').onclick = () => post('trackerAdd');
document.getElementById('trackerRemove').onclick = () => post('trackerRemove');
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') post('close');
});
