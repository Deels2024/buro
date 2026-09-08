// Older home-screen installations still start at the public home page.
// Keep the manifest identity and move those launches into the app on this origin.
(() => {
  const standalone = navigator.standalone === true ||
    (typeof window.matchMedia === 'function' &&
      window.matchMedia('(display-mode: standalone)').matches);
  if (standalone && window.location.pathname === '/') {
    window.location.replace('/app/' + window.location.search + window.location.hash);
  }
})();
