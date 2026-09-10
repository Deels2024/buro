'use strict';
(() => {
  const status = document.getElementById('status');
  const locate = document.getElementById('locate');
  let config, map, pin, loading = false, lastSelected = '', locating = false;
  const send = data => parent.postMessage(JSON.stringify({source: 'bureau-yandex', ...data}), location.origin);
  const valid = point => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite) && Math.abs(point[0]) <= 90 && Math.abs(point[1]) <= 180;
  function pick(point) {
    if (!valid(point) || !config.editable) return;
    if (pin) pin.geometry.setCoordinates(point);
    else { pin = new ymaps.Placemark(point, {}, {preset: 'islands#blueDotIcon'}); map.geoObjects.add(pin); }
    send({type: 'pick', lat: point[0], lon: point[1]});
  }
  function render() {
    if (!map) return;
    map.geoObjects.removeAll(); pin = null;
    for (const marker of config.markers || []) {
      if (!valid([marker.lat, marker.lon])) continue;
      const p = new ymaps.Placemark([marker.lat, marker.lon], {}, {preset: 'islands#redDotIcon'});
      p.events.add('click', () => send({type: 'open', index: marker.index})); map.geoObjects.add(p);
    }
    const selected = valid(config.selected) ? config.selected : null;
    if (selected) {
      pin = new ymaps.Placemark(selected, {}, {preset: 'islands#blueDotIcon', draggable: config.editable});
      pin.events.add('dragend', () => pick(pin.geometry.getCoordinates())); map.geoObjects.add(pin);
      if (JSON.stringify(selected) !== lastSelected) map.setCenter(selected, Math.max(map.getZoom(), 15));
    }
    lastSelected = JSON.stringify(selected);
    locate.hidden = !config.editable;
  }
  function start() {
    if (!config || map || loading) return;
    loading = true;
    const script = document.createElement('script');
    const timer = setTimeout(() => { status.textContent = 'Карта не загрузилась. Адрес можно ввести вручную.'; }, 15000);
    script.src = 'https://api-maps.yandex.ru/2.1/?lang=ru_RU&apikey=' + encodeURIComponent(config.key);
    script.onerror = () => { clearTimeout(timer); status.textContent = 'Карта недоступна. Проверьте соединение или введите адрес вручную.'; };
    script.onload = () => {
      if (!window.ymaps) { status.textContent = 'Не удалось подключить карту.'; return; }
      ymaps.ready(() => {
        clearTimeout(timer);
        try {
          const first = config.markers && config.markers[0];
          const center = valid(config.selected) ? config.selected : first && valid([first.lat, first.lon]) ? [first.lat, first.lon] : [55.75, 37.62];
          map = new ymaps.Map('map', {center, zoom: config.selected || first ? 12 : 4, controls: ['zoomControl']});
          map.events.add('click', event => pick(event.get('coords')));
          status.textContent = config.editable ? 'Нажмите на карту или определите своё местоположение.' : 'Показаны приблизительные места находок и пропаж.';
          render();
        } catch (_) { status.textContent = 'Карта не запустилась. Адрес можно ввести вручную.'; }
      });
    };
    document.head.appendChild(script);
  }
  window.addEventListener('message', event => {
    if (event.origin !== location.origin || event.source !== parent || typeof event.data !== 'string') return;
    try {
      const data = JSON.parse(event.data);
      if (data.source !== 'bureau-flutter' || typeof data.key !== 'string' || !data.key) return;
      config = data; if (map) render(); else start();
    } catch (_) { /* Ignore unrelated messages. */ }
  });
  locate.addEventListener('click', () => {
    if (!navigator.geolocation || !map || locating) { status.textContent = 'Геолокация недоступна. Выберите точку на карте.'; return; }
    locating = true; locate.disabled = true; status.textContent = 'Определяем местоположение…';
    navigator.geolocation.getCurrentPosition(position => {
      locating = false; locate.disabled = false;
      const point = [position.coords.latitude, position.coords.longitude];
      map.setCenter(point, 16); pick(point); status.textContent = 'Проверьте точку и адрес. При необходимости переместите метку.';
    }, error => {
      locating = false; locate.disabled = false;
      status.textContent = error.code === 1 ? 'Разрешите геолокацию в настройках браузера или выберите место вручную.' : 'Не удалось определить место. Выберите точку на карте.';
    }, {enableHighAccuracy: true, timeout: 12000, maximumAge: 60000});
  });
  send({type: 'ready'});
})();
