console.log('fetch available:', typeof fetch !== 'undefined');
if (typeof fetch !== 'undefined') {
  fetch('https://httpbin.org/get').then(r => r.json()).then(j => console.log('ok', !!j.url)).catch(e => console.error('fetch error', e));
} else {
  console.log('no fetch');
}
