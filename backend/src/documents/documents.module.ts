import { Module } from '@nestjs/common';
import { DocumentsController } from './documents.controller.js';
import { DocumentsService } from './documents.service.js';
import { PassSigningService } from './pass-signing.service.js';

@Module({
  controllers: [DocumentsController],
  providers: [DocumentsService, PassSigningService],
  exports: [DocumentsService, PassSigningService],
})
export class DocumentsModule {}
