{{flutter_js}}
{{flutter_build_config}}

(function () {
  function isLocalHarnessRuntime() {
    return window.location.hostname === '127.0.0.1' ||
      window.location.hostname === 'localhost';
  }

  async function unregisterLegacyServiceWorkers() {
    if (!('serviceWorker' in navigator)) {
      return;
    }

    const applicationOrigin = window.location.origin;
    const pushWorkerScope = `${applicationOrigin}/push/`;

    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(
        registrations.map(async (registration) => {
          if (registration.scope === pushWorkerScope) {
            return;
          }

          try {
            await registration.unregister();
          } catch (error) {
            console.warn('Failed to unregister a stale service worker.', error);
          }
        }),
      );
    } catch (error) {
      console.warn('Failed to inspect service workers before bootstrapping.', error);
    }
  }

  async function clearLocalCaches() {
    if (!isLocalHarnessRuntime() || !('caches' in window)) {
      return;
    }

    try {
      const cacheKeys = await window.caches.keys();
      await Promise.all(cacheKeys.map((key) => window.caches.delete(key)));
    } catch (error) {
      console.warn('Failed to clear local browser caches before bootstrapping.', error);
    }
  }

  async function bootstrapFlutterApp() {
    await unregisterLegacyServiceWorkers();
    await clearLocalCaches();
    await _flutter.loader.load();
  }

  bootstrapFlutterApp();
})();
