import { NestFactory } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import type { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { AppModule } from './app.module.js';
import type { Env } from './config/env.js';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bodyParser: false,
  });
  const config = app.get(ConfigService<Env, true>);

  app.set('trust proxy', config.get('TRUST_PROXY_HOPS'));
  app.enableShutdownHooks();
  app.use(
    helmet({
      contentSecurityPolicy: false,
      hsts: config.get('NODE_ENV') === 'production',
      crossOriginResourcePolicy: { policy: 'cross-origin' },
    }),
  );
  app.enableCors({
    origin: config.get('TRUSTED_ORIGINS'),
    credentials: true,
    exposedHeaders: ['set-auth-token'],
  });

  await app.listen(config.get('PORT'));
}

await bootstrap();
