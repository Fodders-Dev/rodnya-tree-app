{{flutter_js}}
{{flutter_build_config}}

(function () {
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

  async function bootstrapFlutterApp() {
    await unregisterLegacyServiceWorkers();
    await _flutter.loader.load();
  }

  bootstrapFlutterApp();
})();
