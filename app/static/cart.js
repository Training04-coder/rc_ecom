// BricoShop : page panier (quantités, suppression, commande simulée)
const $ = (s) => document.querySelector(s);
const price = new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' });
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

function message(text, ok) {
  const m = $('#cart-msg');
  m.textContent = text;
  m.classList.toggle('alert--ok', !!ok);
  m.hidden = false;
}

function render({ items, cartTotal, cartSize }) {
  $('#lines').innerHTML = items.length ? items.map(({ product: p, quantity: q }) => `
    <li class="line" data-id="${p.id}">
      <img class="line__img" src="${esc(p.image)}" alt="" onerror="this.style.visibility='hidden'">
      <div class="line__info">
        <span class="tag">${esc(p.category)}</span>
        <strong>${esc(p.name)}</strong>
        <span class="muted">${price.format(p.price)} l'unité</span>
      </div>
      <div class="qty" role="group" aria-label="Quantité">
        <button type="button" data-qty="${q - 1}" aria-label="Diminuer">−</button>
        <span>${q}</span>
        <button type="button" data-qty="${q + 1}" aria-label="Augmenter">+</button>
      </div>
      <strong class="line__total">${price.format(p.price * q)}</strong>
      <button class="line__remove" type="button" data-remove aria-label="Supprimer ${esc(p.name)}">×</button>
    </li>`).join('') : '<li class="muted">Votre panier est vide. <a href="/">Découvrir nos produits</a></li>';
  $('#sum-size').textContent = cartSize;
  $('#sum-total').textContent = price.format(cartTotal);
  $('#checkout').disabled = !items.length;
}

async function call(url, method, body) {
  const res = await fetch(url, { method, body: body && new URLSearchParams(body) });
  if (res.status === 401) { location.href = '/login'; return null; }
  return res;
}

$('#lines').addEventListener('click', async (e) => {
  const line = e.target.closest('.line');
  if (!line) return;
  const url = `/api/cart/${line.dataset.id}`;
  const qty = e.target.closest('[data-qty]');
  const res = qty ? await call(url, 'PUT', { quantity: qty.dataset.qty })
            : e.target.closest('[data-remove]') ? await call(url, 'DELETE') : null;
  if (res && res.ok) render(await res.json());
});

$('#checkout').addEventListener('click', async () => {
  $('#checkout').disabled = true;
  const res = await call('/api/checkout', 'POST');
  if (!res) return;
  if (res.ok) {
    const { orderId, cartTotal } = await res.json();
    message(`Merci ! Commande ${orderId} confirmée (${price.format(cartTotal)}).`, true);
  } else {
    message('Le paiement a échoué, votre panier est conservé. Réessayez dans un instant.');
  }
  const cart = await call('/api/cart', 'GET');
  if (cart && cart.ok) render(await cart.json());
});

call('/api/cart', 'GET').then(async (res) => { if (res && res.ok) render(await res.json()); });
