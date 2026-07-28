import { Router, Request, Response } from 'express';
import { readFileSync } from 'fs';
import { join } from 'path';

const router: Router = Router();

let nodeVersion = 'unknown';
try {
  const pkg = JSON.parse(readFileSync(join(__dirname, '../../package.json'), 'utf-8'));
  nodeVersion = pkg.version ? `${pkg.version}_f_gds` : 'unknown';
} catch {}

router.get('/', (_req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), version: nodeVersion });
});

export default router;
