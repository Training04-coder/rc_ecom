// BricoShop : vitrine (catalogue, filtres, modale de détail). Aucun framework.
const $ = (s) => document.querySelector(s);
const price = new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' });
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const COLORS = { 'Électroportatif': '#f2681c', 'Outillage à main': '#2f6fb3', 'Mesure': '#2e9a6a', 'Peinture': '#b04aa8', 'Quincaillerie': '#7a6a55' };

// Illustration SVG de secours si l'image distante est introuvable
function fallbackImage(category) {
  const c = COLORS[category] || '#5d6675';
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 400">
    <rect width="600" height="400" fill="${c}" opacity=".12"/>
    <g transform="translate(300 170) rotate(-35)" fill="${c}">
      <rect x="-14" y="-20" width="28" height="150" rx="10"/>
      <path d="M-70 -70h120l30 25v25h-150z"/>
    </g>
    <text x="300" y="350" text-anchor="middle" font-family="system-ui,sans-serif" font-size="28" font-weight="600" fill="${c}">${esc(category)}</text>
  </svg>`;
  return 'data:image/svg+xml,' + encodeURIComponent(svg);
}

function withFallback(img, category) {
  img.onerror = () => { img.onerror = null; img.src = fallbackImage(category); };
}

let products = [];
let current = 'Tout';

function renderFilters() {
  const cats = ['Tout', ...new Set(products.map((p) => p.category))];
  $('#filters').innerHTML = cats.map((c) =>
    `<button class="chip" type="button" aria-pressed="${c === current}" data-cat="${esc(c)}">${esc(c)}</button>`).join('');
}

function renderGrid() {
  const list = current === 'Tout' ? products : products.filter((p) => p.category === current);
  $('#grid').innerHTML = list.map((p) => `
    <article class="card" tabindex="0" data-id="${p.id}" aria-label="${esc(p.name)}">
      <img class="card__img" src="${esc(p.image)}" alt="${esc(p.name)}" loading="lazy" data-cat="${esc(p.category)}">
      <div class="card__body">
        <span class="tag">${esc(p.category)}</span>
        <h3>${esc(p.name)}</h3>
        <p>${esc(p.description)}</p>
        <div class="card__foot">
          <strong class="price">${price.format(p.price)}</strong>
          <button class="btn" type="button" data-add="${p.id}">Ajouter</button>
        </div>
      </div>
    </article>`).join('');
  document.querySelectorAll('.card__img').forEach((img) => withFallback(img, img.dataset.cat));
}

// Chaque ouverture appelle l'API détail : c'est elle qui produit le log product_view
async function openProduct(id) {
  const res = await fetch(`/api/products/${id}`);
  if (!res.ok) return;
  const p = await res.json();
  const img = $('#modal-img');
  withFallback(img, p.category);
  img.src = p.image;
  img.alt = p.name;
  $('#modal-cat').textContent = p.category;
  $('#modal-title').textContent = p.name;
  $('#modal-desc').textContent = p.description;
  $('#modal-price').textContent = price.format(p.price);
  $('#modal-add').dataset.add = p.id;
  $('#modal').showModal();
}

$('#filters').addEventListener('click', (e) => {
  const b = e.target.closest('.chip');
  if (!b) return;
  current = b.dataset.cat;
  renderFilters();
  renderGrid();
});

// Ajout au panier : redirige vers /login si non connecté
async function addToCart(id) {
  const res = await fetch('/api/cart', { method: 'POST', body: new URLSearchParams({ productId: id, quantity: 1 }) });
  if (res.status === 401) { location.href = '/login'; return; }
  if (!res.ok) { toast("Impossible d'ajouter ce produit."); return; }
  $('#cart-count').textContent = (await res.json()).cartSize;
  toast('Ajouté au panier ✓');
}

let toastTimer;
function toast(msg) {
  const t = $('#toast');
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 2200);
}

$('#grid').addEventListener('click', (e) => {
  const add = e.target.closest('[data-add]');
  if (add) { addToCart(add.dataset.add); return; }
  const card = e.target.closest('.card');
  if (card) openProduct(card.dataset.id);
});
$('#modal-add').addEventListener('click', (e) => { addToCart(e.target.dataset.add); $('#modal').close(); });
$('#grid').addEventListener('keydown', (e) => {
  const card = e.target.closest('.card');
  if (card && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); openProduct(card.dataset.id); }
});

const modal = $('#modal');
modal.addEventListener('click', (e) => {
  if (e.target === modal || e.target.closest('[data-close]')) modal.close();
});

// Etat de connexion dans le header
fetch('/api/me').then((r) => r.json()).then(({ email, cartSize }) => {
  $('#cart-count').textContent = cartSize;
  if (!email) return;
  $('#account').innerHTML = `<span class="account__email" title="${esc(email)}">${esc(email)}</span>
    <button class="link" type="button" id="logout">Déconnexion</button>`;
  $('#logout').addEventListener('click', () => fetch('/api/logout', { method: 'POST' }).then(() => location.reload()));
});

fetch('/api/products')
  .then((r) => r.json())
  .then((data) => { products = data; renderFilters(); renderGrid(); })
  .catch(() => { $('#grid').innerHTML = '<p class="muted">Catalogue indisponible, réessayez plus tard.</p>'; });
