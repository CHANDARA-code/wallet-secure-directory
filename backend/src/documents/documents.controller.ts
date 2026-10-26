import {
  Controller,
  Get,
  Header,
  Inject,
  Param,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Response } from 'express';
import type { AuthSession } from '../auth/auth.factory.js';
import { AuthGuard, CurrentSession } from '../auth/auth.guard.js';
import { DocumentsService } from './documents.service.js';

@Controller('api/documents')
@UseGuards(AuthGuard)
export class DocumentsController {
  constructor(
    @Inject(DocumentsService)
    private readonly documentsService: DocumentsService,
  ) {}

  @Get()
  @Header('Cache-Control', 'no-store')
  list(@CurrentSession() session: AuthSession) {
    return this.documentsService.listUserDocuments(session.user.id);
  }

  @Get(':id')
  @Header('Cache-Control', 'no-store')
  getOne(@CurrentSession() session: AuthSession, @Param('id') id: string) {
    return this.documentsService.getUserDocument(id, session.user.id);
  }

  @Get(':id/pass/apple')
  @Header('Cache-Control', 'no-store')
  async getApplePass(
    @CurrentSession() session: AuthSession,
    @Param('id') id: string,
    @Res() res: Response,
  ) {
    const { documentNumber, zipBuffer, isStub } =
      await this.documentsService.getApplePass(id, session.user.id);

    res.setHeader('Content-Type', 'application/vnd.apple.pkpass');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${documentNumber}.pkpass"`,
    );
    res.setHeader('X-Pass-Stub', isStub ? 'true' : 'false');
    res.setHeader('Cache-Control', 'no-store');
    res.send(zipBuffer);
  }

  @Get(':id/pass/google')
  @Header('Cache-Control', 'no-store')
  getGooglePass(
    @CurrentSession() session: AuthSession,
    @Param('id') id: string,
  ) {
    return this.documentsService.getGooglePass(id, session.user.id);
  }
}
