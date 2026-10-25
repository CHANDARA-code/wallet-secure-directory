import {
  ExecutionContext,
  ForbiddenException,
  Inject,
  Injectable,
} from '@nestjs/common';
import { eq } from 'drizzle-orm';
import { AUTH } from '../auth/auth.constants.js';
import type { Auth } from '../auth/auth.factory.js';
import { AuthGuard, type AuthenticatedRequest } from '../auth/auth.guard.js';
import { DRIZZLE, type AppDatabase } from '../database/database.module.js';
import * as schema from '../database/schema.js';

@Injectable()
export class AdminGuard extends AuthGuard {
  constructor(
    @Inject(AUTH) auth: Auth,
    @Inject(DRIZZLE) private readonly db: AppDatabase,
  ) {
    super(auth);
  }

  override async canActivate(context: ExecutionContext): Promise<boolean> {
    await super.canActivate(context);
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const userId = request.authSession.user.id;
    const currentUser = this.db
      .select({ role: schema.user.role })
      .from(schema.user)
      .where(eq(schema.user.id, userId))
      .get();

    if (!currentUser || currentUser.role !== 'admin') {
      throw new ForbiddenException('Admin access required');
    }
    return true;
  }
}
