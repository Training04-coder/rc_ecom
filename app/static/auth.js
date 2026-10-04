// BricoShop : pages /login et /signup (même HTML, le mode dépend de l'URL)
const signup = location.pathname === '/signup';
const form = document.getElementById('auth-form');
const error = document.getElementById('auth-error');
const MESSAGES = {
  invalid_credentials: 'E-mail ou mot de passe incorrect.',
  invalid_email: 'Adresse e-mail invalide.',
  weak_password: 'Le mot de passe doit contenir au moins 8 caractères.',
  email_taken: 'Un compte existe déjà avec cette adresse.',
};

if (signup) {
  document.title = 'Créer un compte — BricoShop';
  document.getElementById('auth-title').textContent = 'Créer un compte';
  document.getElementById('auth-lead').textContent = 'Quelques secondes suffisent pour commencer vos achats.';
  document.getElementById('auth-submit').textContent = 'Créer mon compte';
  document.getElementById('auth-switch').innerHTML = 'Déjà inscrit ? <a href="/login">Se connecter</a>';
  form.password.autocomplete = 'new-password';
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  error.hidden = true;
  const res = await fetch(signup ? '/api/signup' : '/api/login', { method: 'POST', body: new URLSearchParams(new FormData(form)) });
  if (res.ok) { location.href = '/'; return; }
  const { error: code } = await res.json().catch(() => ({}));
  error.textContent = MESSAGES[code] || 'Une erreur est survenue, réessayez.';
  error.hidden = false;
});
