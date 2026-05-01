self.addEventListener('push', (event) => {
  event.waitUntil(handlePushEvent(event));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(openNotificationTarget(event.notification));
});

async function handlePushEvent(event) {
  const payload = parsePayload(event);
  const clientList = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });
  const hasVisibleClient = clientList.some((client) => {
    try {
      return (
        new URL(client.url).origin === self.location.origin &&
        client.visibilityState === 'visible'
      );
    } catch (_) {
      return false;
    }
  });

  if (hasVisibleClient) {
    return;
  }

  await self.registration.showNotification(payload.title, {
    body: payload.body,
    tag: payload.tag,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    renotify: payload.renotify,
    requireInteraction: payload.requireInteraction,
    silent: false,
    timestamp: payload.timestamp,
    data: {
      url: payload.url,
      payload: payload.payload,
      event: payload.event,
    },
  });
}

async function openNotificationTarget(notification) {
  const data = notification.data || {};
  const targetUrl = data.url || '/#/notifications';
  const clientList = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });

  for (const client of clientList) {
    try {
      if (new URL(client.url).origin !== self.location.origin) {
        continue;
      }
      await client.focus();
      if ('navigate' in client) {
        await client.navigate(targetUrl);
      }
      return;
    } catch (_) {}
  }

  await self.clients.openWindow(targetUrl);
}

function parsePayload(event) {
  const fallback = {
    title: 'Родня',
    body: '',
    tag: `rodnya-${Date.now()}`,
    url: '/#/notifications',
    payload: null,
    event: null,
    renotify: false,
    requireInteraction: false,
    timestamp: Date.now(),
  };

  if (!event.data) {
    return fallback;
  }

  try {
    const parsed = event.data.json();
    return {
      title: parsed.title || fallback.title,
      body: parsed.body || fallback.body,
      tag: parsed.tag || fallback.tag,
      url: parsed.url || fallback.url,
      payload: parsed.payload || fallback.payload,
      event: parsed.event || fallback.event,
      renotify: parsed.renotify === true,
      requireInteraction: parsed.requireInteraction === true,
      timestamp: Number(parsed.timestamp || Date.now()),
    };
  } catch (_) {
    return fallback;
  }
}
