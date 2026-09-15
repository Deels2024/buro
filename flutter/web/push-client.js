/* Explicit opt-in only. This worker does not replace Flutter's cache worker. */
(() => {
  const deviceKey = 'bureau.push.device.v1';
  const supported = window.isSecureContext && 'serviceWorker' in navigator &&
    'PushManager' in window && 'Notification' in window;
  const registration = () => navigator.serviceWorker.register('/app/bureau-push-sw.js', {scope: '/app/push/'});
  const active = async () => {
    const reg = await registration();
    if (!reg.active) await new Promise((resolve, reject) => {
      const worker = reg.installing || reg.waiting;
      if (!worker) return reject(new Error('Не удалось подготовить уведомления'));
      const timer = setTimeout(() => reject(new Error('Подготовка уведомлений заняла слишком много времени')), 10000);
      worker.addEventListener('statechange', () => {
        if (worker.state === 'activated') { clearTimeout(timer); resolve(); }
        if (worker.state === 'redundant') { clearTimeout(timer); reject(new Error('Обновите приложение и попробуйте ещё раз')); }
      });
    });
    return reg;
  };
  window.bureauPush = {
    supported,
    async subscription() {
      if (!supported) return '';
      const reg = await navigator.serviceWorker.getRegistration('/app/push/');
      const sub = reg && await reg.pushManager.getSubscription();
      return sub ? JSON.stringify(sub.toJSON()) : '';
    },
    async subscribe(publicKey) {
      if (!supported) throw new Error('Откройте установленное приложение с экрана «Домой»');
      // Must run synchronously inside the button's user gesture on iOS.
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') throw new Error('Разрешите уведомления для приложения в настройках телефона или браузера');
      const reg = await active();
      const bytes = Uint8Array.from(atob(publicKey.replace(/-/g, '+').replace(/_/g, '/')), ch => ch.charCodeAt(0));
      let sub = await reg.pushManager.getSubscription();
      if (sub && sub.options.applicationServerKey &&
          String(new Uint8Array(sub.options.applicationServerKey)) !== String(bytes)) {
        await sub.unsubscribe(); sub = null;
      }
      sub = sub || await reg.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: bytes});
      return JSON.stringify(sub.toJSON());
    },
    saveDevice(id) { localStorage.setItem(deviceKey, id); },
    async unsubscribe() {
      const id = localStorage.getItem(deviceKey) || '';
      if (supported) {
        const reg = await navigator.serviceWorker.getRegistration('/app/push/');
        const sub = reg && await reg.pushManager.getSubscription();
        if (sub) await sub.unsubscribe();
      }
      localStorage.removeItem(deviceKey);
      return id;
    }
  };
})();
