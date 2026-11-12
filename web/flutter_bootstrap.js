{{flutter_js}}
{{flutter_build_config}}

const nativeShell = new URLSearchParams(window.location.search).has('native_build');
const localDemo = ['localhost', '127.0.0.1', '::1'].includes(window.location.hostname);
const buildVersion = {{flutter_service_worker_version}};
if (nativeShell || localDemo) {
  // A previous loopback service worker can otherwise keep the old guide alive.
  // Querying the generated entrypoint by build version bypasses that stale cache.
  for (const build of _flutter.buildConfig.builds) {
    if (build.mainJsPath) build.mainJsPath += '?build=' + encodeURIComponent(buildVersion);
  }
  navigator.serviceWorker?.getRegistrations().then(registrations => {
    const appScope = new URL('./', document.baseURI).href;
    for (const registration of registrations) {
      if (registration.scope === appScope) registration.unregister();
    }
  });
}
_flutter.loader.load({
  ...(nativeShell || localDemo ? {} : {
    serviceWorkerSettings: { serviceWorkerVersion: buildVersion },
  }),
  config: { canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).toString() },
});
