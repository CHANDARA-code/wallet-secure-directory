import {
  Body,
  Controller,
  Get,
  Header,
  HttpCode,
  HttpStatus,
  Inject,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import type { AuthSession } from '../auth/auth.factory.js';
import { CurrentSession } from '../auth/auth.guard.js';
import {
  adminDocumentsQuerySchema,
  adminUsersQuerySchema,
  issueDocumentSchema,
  parseOrThrowBadRequest,
} from '../documents/documents.schema.js';
import { AdminGuard } from './admin.guard.js';
import { AdminService } from './admin.service.js';

@Controller('api/admin')
@UseGuards(AdminGuard)
export class AdminController {
  constructor(
    @Inject(AdminService) private readonly adminService: AdminService,
  ) {}

  @Get('users')
  @Header('Cache-Control', 'no-store')
  listUsers(@Query() query: unknown) {
    const parsed = parseOrThrowBadRequest(adminUsersQuerySchema, query);
    return this.adminService.listUsers(parsed);
  }

  @Get('documents')
  @Header('Cache-Control', 'no-store')
  listDocuments(@Query() query: unknown) {
    const parsed = parseOrThrowBadRequest(adminDocumentsQuerySchema, query);
    return this.adminService.listDocuments(parsed);
  }

  @Post('documents')
  @HttpCode(HttpStatus.CREATED)
  @Header('Cache-Control', 'no-store')
  issueDocument(@CurrentSession() session: AuthSession, @Body() body: unknown) {
    const parsed = parseOrThrowBadRequest(issueDocumentSchema, body);
    return this.adminService.issueDocument(session.user.id, parsed);
  }

  @Post('documents/:id/revoke')
  @HttpCode(HttpStatus.OK)
  @Header('Cache-Control', 'no-store')
  revokeDocument(@Param('id') id: string) {
    return this.adminService.revokeDocument(id);
  }
}
