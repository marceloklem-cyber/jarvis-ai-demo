/* JARVIS AI — service worker mínimo (0.7).
 * Serve apenas para exibir notificações no Chrome Android, que não aceita `new Notification()`.
 * Não guarda cache: cada visita carrega a versão mais recente do index.html.
 * Não agenda nada sozinho: os avisos continuam dependendo da página aberta.
 */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of all) { if ('focus' in c) return c.focus(); }
    return self.clients.openWindow ? self.clients.openWindow('./') : undefined;
  })());
});
