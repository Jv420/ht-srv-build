'use strict';

const panel = document.querySelector('#panel');
const title = document.querySelector('#title');
const subtitle = document.querySelector('#subtitle');
const result = document.querySelector('#result');
const ticketPanel = document.querySelector('#ticket-panel');
const ticketSelect = document.querySelector('#ticket-select');
const arrestStatus = document.querySelector('#arrest-status');
const escortStatus = document.querySelector('#escort-status');
let state = null;

async function post(endpoint, body = {}) {
  await fetch(`https://${GetParentResourceName()}/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(body)
  });
}

function updateStatus(data = {}) {
  const arrested = Boolean(data.arrested);
  const escorted = Boolean(data.escorted);
  arrestStatus.textContent = arrested ? 'Aangehouden' : 'Niet aangehouden';
  arrestStatus.classList.toggle('active', arrested);
  escortStatus.textContent = escorted ? 'Escort actief' : 'Geen escort';
  escortStatus.classList.toggle('active', escorted);
}

function showResult(data = {}) {
  result.innerHTML = '';
  const heading = document.createElement('h2');
  heading.textContent = data.title || 'Controle';
  result.append(heading);
  for (const line of data.lines || [data.message || 'Handeling verwerkt.']) {
    const paragraph = document.createElement('p');
    paragraph.textContent = line;
    result.append(paragraph);
  }
  if (data.subtitle) subtitle.textContent = data.subtitle;
  updateStatus(data);
}

function open(data) {
  state = data;
  title.textContent = data.title || 'NPC politiecontrole';
  subtitle.textContent = data.subtitle || 'Identiteit nog niet vastgesteld';
  ticketSelect.innerHTML = '';
  for (const ticket of data.tickets || []) {
    const option = document.createElement('option');
    option.value = ticket.code;
    option.textContent = `${ticket.code} — ${ticket.label} (€${ticket.amount})`;
    ticketSelect.append(option);
  }
  updateStatus(data);
  result.innerHTML = '<h2>Controle</h2><p>Selecteer een handeling.</p>';
  ticketPanel.classList.add('hidden');
  panel.classList.remove('hidden');
  panel.setAttribute('aria-hidden', 'false');
}

function close() {
  state = null;
  panel.classList.add('hidden');
  panel.setAttribute('aria-hidden', 'true');
}

document.querySelector('#actions').addEventListener('click', (event) => {
  const action = event.target.dataset.action;
  if (action) post('action', { action });
});

document.querySelector('#ticket-button').addEventListener('click', () => {
  ticketPanel.classList.remove('hidden');
});
document.querySelector('#ticket-cancel').addEventListener('click', () => {
  ticketPanel.classList.add('hidden');
});
document.querySelector('#ticket-confirm').addEventListener('click', () => {
  if (!ticketSelect.value) return;
  post('action', { action: 'ticket', payload: { code: ticketSelect.value } });
  ticketPanel.classList.add('hidden');
});
document.querySelector('#close').addEventListener('click', () => post('close'));

document.addEventListener('keyup', (event) => {
  if (event.key === 'Escape') post('close');
});

window.addEventListener('message', ({ data }) => {
  if (data?.type === 'open') open(data.data || {});
  if (data?.type === 'result') showResult(data.data || {});
  if (data?.type === 'close') close();
});
