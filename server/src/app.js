import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import { env } from './config/env.js';
import { isDatabaseReady } from './config/db.js';
import { generalLimiter } from './middleware/rateLimits.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import authRoutes from './routes/auth.js';
import profileRoutes from './routes/profile.js';
import { opportunitiesRouter, savedRouter, matchesRouter, eligibilityRouter } from './routes/opportunities.js';
import applicationRoutes from './routes/applications.js';
import roadmapRoutes from './routes/roadmap.js';
import aiRoutes from './routes/ai.js';
import draftRoutes from './routes/drafts.js';
import { campusRouter, collegesRouter, meRouter, resourcesRouter } from './routes/campus.js';
import adminRoutes from './routes/admin.js';
import { getAIProvider } from './ai/provider.js';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  if (env.TRUST_PROXY) app.set('trust proxy', env.TRUST_PROXY);

  app.use(helmet());
  // The iOS app does not need CORS; browser origins must be allow-listed.
  const origins = env.CORS_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean);
  app.use(cors({ origin: origins.length ? origins : false }));
  app.use(express.json({ limit: '200kb' }));

  app.get('/health', (_req, res) => res.json({ status: 'ok', uptimeSeconds: Math.round(process.uptime()) }));
  app.get('/ready', (_req, res) => {
    const db = isDatabaseReady();
    res.status(db ? 200 : 503).json({ status: db ? 'ready' : 'not_ready', database: db ? 'connected' : 'disconnected', ai: getAIProvider() ? 'configured' : 'not_configured' });
  });

  app.use('/api', generalLimiter);
  app.use('/api/auth', authRoutes);
  app.use('/api/profile', profileRoutes);
  app.use('/api/colleges', collegesRouter);
  app.use('/api/opportunities', opportunitiesRouter);
  app.use('/api/saved', savedRouter);
  app.use('/api/matches', matchesRouter);
  app.use('/api/eligibility', eligibilityRouter);
  app.use('/api/applications', applicationRoutes);
  app.use('/api/roadmap', roadmapRoutes);
  app.use('/api/ai', aiRoutes);
  app.use('/api/drafts', draftRoutes);
  app.use('/api/campus', campusRouter);
  app.use('/api/me', meRouter);
  app.use('/api/resources', resourcesRouter);
  app.use('/api/admin', adminRoutes);

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
