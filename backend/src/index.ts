import express from 'express';
import cors from 'cors';
import { execFile } from 'child_process';
import { readFileSync } from 'fs';
import { join } from 'path';
import { config } from './config';
import { runMigrations, createAdminUser } from './db/migrations';
import { authMiddleware } from './middleware/auth';
import authRoutes from './routes/auth';
import nodeRoutes from './routes/nodes';
import proxyRoutes from './routes/proxies';
import allProxiesRoutes from './routes/allProxies';

const app = express();

app.use(cors());
app.use(express.json());

app.use('/api/auth', authRoutes);
app.use('/api/nodes', nodeRoutes);
app.use('/api/nodes', proxyRoutes);
app.use('/api/proxies', allProxiesRoutes);

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok' });
});

app.get('/api/system/version', authMiddleware, (_req, res) => {
  let version = 'unknown';
  try {
    const pkg = JSON.parse(readFileSync(join(__dirname, '../package.json'), 'utf-8'));
    version = pkg.version ? `${pkg.version}_f_gds` : 'unknown';
  } catch {}
  res.json({ version });
});

// Trigger panel self-update (fires update.sh and returns immediately)
app.post('/api/system/update', authMiddleware, (_req, res) => {
  const scriptPath = '/app/project/update.sh';
  // Fire and forget — container will rebuild itself
  execFile('/bin/bash', [scriptPath], { cwd: '/app/project', timeout: 300000 }, () => {});
  res.json({ success: true, message: 'Обновление запущено. Панель перезапустится через несколько минут.' });
});

async function bootstrap(): Promise<void> {
  try {
    await runMigrations();

    const adminUser = process.env.ADMIN_USERNAME;
    const adminPass = process.env.ADMIN_PASSWORD;
    if (adminUser && adminPass) {
      await createAdminUser(adminUser, adminPass);
    }

    app.listen(config.port, '0.0.0.0', () => {
      console.log(`Panel backend running on port ${config.port}`);
    });
  } catch (error) {
    console.error('Failed to start panel backend:', error);
    process.exit(1);
  }
}

bootstrap();
