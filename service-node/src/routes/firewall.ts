import { Router, Request, Response } from 'express';
import { applyFirewallPreset, getFirewallStatus } from '../services/firewall';
import { applyAllMekoRecommendations } from '../services/meko';

const router: Router = Router();

router.get('/', async (_req: Request, res: Response) => {
  try {
    res.json(await getFirewallStatus());
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

router.put('/', async (req: Request, res: Response) => {
  try {
    res.json(await applyFirewallPreset(req.body?.preset, req.body?.ports));
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
});

router.post('/apply-all', async (_req: Request, res: Response) => {
  try {
    const result = await applyAllMekoRecommendations();
    res.status(result.success ? 200 : 207).json(result);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

export default router;
