import { $, api } from './common.js';

api('GET', '/api/me').then(
  () => location.replace('/app'),
  () => {}
);

function selectTab(name) {
  for (const tab of ['login', 'signup']) {
    $(`#tab-${tab}`).setAttribute('aria-selected', String(tab === name));
    $(`#${tab}-form`).hidden = tab !== name;
  }
  $(`#${name}-form input`).focus();
}

$('#tab-login').addEventListener('click', () => selectTab('login'));
$('#tab-signup').addEventListener('click', () => selectTab('signup'));
if (location.hash === '#inscription') selectTab('signup');

function handle(form, path, next) {
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const button = form.querySelector('button[type="submit"]');
    const error = form.querySelector('.error');
    button.disabled = true;
    error.textContent = '';
    try {
      await api('POST', path, Object.fromEntries(new FormData(form)));
      location.href = next;
    } catch (err) {
      error.textContent = err.message;
      button.disabled = false;
    }
  });
}

handle($('#login-form'), '/api/login', '/app');
handle($('#signup-form'), '/api/signup', '/reglages?bienvenue=1');
