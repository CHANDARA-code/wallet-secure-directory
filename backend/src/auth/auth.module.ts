import { Global, MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { json } from 'express';
import type { Env } from '../config/env.js';
import { DRIZZLE, type AppDatabase } from '../database/database.module.js';
import { AUTH } from './auth.constants.js';
import { AUTH_BASE_PATH, createAuth } from './auth.factory.js';
import { AuthGuard } from './auth.guard.js';
import { AuthMiddleware } from './auth.middleware.js';

@Global()
@Module({
  providers: [
    {
      provide: AUTH,
      inject: [DRIZZLE, ConfigService],
      useFactory: (db: AppDatabase, config: ConfigService<Env, true>) =>
        createAuth(db, {
          BETTER_AUTH_SECRET: config.get('BETTER_AUTH_SECRET'),
          BETTER_AUTH_URL: config.get('BETTER_AUTH_URL'),
          TRUSTED_ORIGINS: config.get('TRUSTED_ORIGINS'),
          NODE_ENV: config.get('NODE_ENV'),
          TRUST_PROXY_HOPS: config.get('TRUST_PROXY_HOPS'),
        }),
    },
    AuthGuard,
  ],
  exports: [AUTH, AuthGuard],
})
export class AuthModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(AuthMiddleware)
      .forRoutes(`${AUTH_BASE_PATH}/{*path}`)
      .apply(json())
      .exclude(`${AUTH_BASE_PATH}/{*path}`)
      .forRoutes('{*path}');
  }
}
