import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, desc, eq } from 'drizzle-orm';
import { DRIZZLE, type AppDatabase } from '../database/database.module.js';
import * as schema from '../database/schema.js';
import { createApplePassZip } from './apple-pass.util.js';
import {
  createGooglePassStub,
  type GooglePassStub,
} from './google-pass.util.js';

@Injectable()
export class DocumentsService {
  constructor(@Inject(DRIZZLE) private readonly db: AppDatabase) {}

  async listUserDocuments(userId: string) {
    return this.db
      .select({
        id: schema.identityDocument.id,
        type: schema.identityDocument.type,
        documentNumber: schema.identityDocument.documentNumber,
        status: schema.identityDocument.status,
        issuedAt: schema.identityDocument.issuedAt,
        expiresAt: schema.identityDocument.expiresAt,
      })
      .from(schema.identityDocument)
      .where(
        and(
          eq(schema.identityDocument.userId, userId),
          eq(schema.identityDocument.status, 'issued'),
        ),
      )
      .orderBy(desc(schema.identityDocument.issuedAt))
      .all();
  }

  async getUserDocument(id: string, userId: string) {
    const doc = this.db
      .select({
        id: schema.identityDocument.id,
        type: schema.identityDocument.type,
        documentNumber: schema.identityDocument.documentNumber,
        issuedAt: schema.identityDocument.issuedAt,
        expiresAt: schema.identityDocument.expiresAt,
        data: schema.identityDocument.payload,
      })
      .from(schema.identityDocument)
      .where(
        and(
          eq(schema.identityDocument.id, id),
          eq(schema.identityDocument.userId, userId),
          eq(schema.identityDocument.status, 'issued'),
        ),
      )
      .get();

    if (!doc) {
      throw new NotFoundException('Document not found');
    }
    return doc;
  }

  async getApplePass(
    id: string,
    userId: string,
  ): Promise<{ documentNumber: string; zipBuffer: Buffer }> {
    const doc = this.db
      .select({
        documentNumber: schema.identityDocument.documentNumber,
        payload: schema.identityDocument.payload,
      })
      .from(schema.identityDocument)
      .where(
        and(
          eq(schema.identityDocument.id, id),
          eq(schema.identityDocument.userId, userId),
          eq(schema.identityDocument.status, 'issued'),
        ),
      )
      .get();

    if (!doc) {
      throw new NotFoundException('Document not found');
    }

    const zipBuffer = createApplePassZip(doc.documentNumber, doc.payload);
    return {
      documentNumber: doc.documentNumber,
      zipBuffer,
    };
  }

  async getGooglePass(id: string, userId: string): Promise<GooglePassStub> {
    const doc = this.db
      .select({
        documentNumber: schema.identityDocument.documentNumber,
        payload: schema.identityDocument.payload,
      })
      .from(schema.identityDocument)
      .where(
        and(
          eq(schema.identityDocument.id, id),
          eq(schema.identityDocument.userId, userId),
          eq(schema.identityDocument.status, 'issued'),
        ),
      )
      .get();

    if (!doc) {
      throw new NotFoundException('Document not found');
    }

    return createGooglePassStub(doc.documentNumber, doc.payload);
  }
}
