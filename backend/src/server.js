'use strict';

const { loadConfig } = require('./config');
const { createApp } = require('./app');

const config = loadConfig();
const { server } = createApp({ config });

server.listen(config.port, '0.0.0.0', () => {
  console.log(`[server] API Offline-First escuchando en http://0.0.0.0:${config.port}`);
  console.log(`[server] Emulador Android: http://10.0.2.2:${config.port}`);
  console.log(`[server] Consola nube:     http://localhost:${config.port}/console`);
  if (!config.adminPassword) console.log('[server] (define ADMIN_PASSWORD para habilitar la consola)');
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => server.close(() => process.exit(0)));
}
