import { Controller, Get, Inject, UseGuards } from '@nestjs/common';
import type Database from 'better-sqlite3';
import { AuthGuard, CurrentSession } from './auth/auth.guard.js';
import type { AuthSession } from './auth/auth.factory.js';
import { SQLITE } from './database/database.module.js';

@Controller('api')
export class AppController {
  constructor(@Inject(SQLITE) private readonly sqlite: Database.Database) {}

  @Get('health')
  health() {
    const journalMode = this.sqlite.pragma('journal_mode', { simple: true });
    return { status: 'ok', journalMode };
  }

  @Get('me')
  @UseGuards(AuthGuard)
  me(@CurrentSession() session: AuthSession) {
    return { user: session.user };
  }
}
