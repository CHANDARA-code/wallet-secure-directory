import {
  Inject,
  Injectable,
  InternalServerErrorException,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { count, desc, eq, or, sql } from 'drizzle-orm';
import { DRIZZLE, type AppDatabase } from '../database/database.module.js';
import * as schema from '../database/schema.js';
import {
  generateDocumentNumber,
  type AdminDocumentsQuery,
  type AdminUsersQuery,
  type IssueDocumentInput,
} from '../documents/documents.schema.js';

@Injectable()
export class AdminService {
  constructor(@Inject(DRIZZLE) private readonly db: AppDatabase) {}

  async listUsers(query: AdminUsersQuery) {
    const { limit, offset, q } = query;
    const trimmed = q?.trim();
    const escapedQ = trimmed
      ? trimmed.toLowerCase().replace(/[%_\\]/g, '\\$&')
      : '';
    const pattern = `%${escapedQ}%`;
    const filter =
      trimmed && trimmed.length > 0
        ? or(
            sql`lower(${schema.user.name}) LIKE ${pattern} ESCAPE '\\'`,
            sql`lower(${schema.user.email}) LIKE ${pattern} ESCAPE '\\'`,
          )
        : undefined;

    const countQuery = this.db.select({ count: count() }).from(schema.user);

    if (filter) {
      countQuery.where(filter);
    }
    const total = countQuery.get()?.count ?? 0;

    const usersQuery = this.db
      .select({
        id: schema.user.id,
        name: schema.user.name,
        email: schema.user.email,
        role: schema.user.role,
        createdAt: schema.user.createdAt,
        documentCount:
          sql<number>`(select count(*) from identity_document where identity_document.user_id = user.id and identity_document.status = 'issued')`.mapWith(
            Number,
          ),
      })
      .from(schema.user);

    if (filter) {
      usersQuery.where(filter);
    }

    const items = usersQuery
      .orderBy(desc(schema.user.createdAt))
      .limit(limit)
      .offset(offset)
      .all();

    return { items, total };
  }

  async listDocuments(query: AdminDocumentsQuery) {
    const { limit, offset, userId } = query;
    const filter = userId
      ? eq(schema.identityDocument.userId, userId)
      : undefined;

    const countQuery = this.db
      .select({ count: count() })
      .from(schema.identityDocument);

    if (filter) {
      countQuery.where(filter);
    }
    const total = countQuery.get()?.count ?? 0;

    const docsQuery = this.db
      .select({
        id: schema.identityDocument.id,
        userId: schema.identityDocument.userId,
        userEmail: schema.user.email,
        type: schema.identityDocument.type,
        documentNumber: schema.identityDocument.documentNumber,
        status: schema.identityDocument.status,
        issuedAt: schema.identityDocument.issuedAt,
        expiresAt: schema.identityDocument.expiresAt,
        revokedAt: schema.identityDocument.revokedAt,
      })
      .from(schema.identityDocument)
      .innerJoin(
        schema.user,
        eq(schema.identityDocument.userId, schema.user.id),
      );

    if (filter) {
      docsQuery.where(filter);
    }

    const items = docsQuery
      .orderBy(desc(schema.identityDocument.issuedAt))
      .limit(limit)
      .offset(offset)
      .all();

    return { items, total };
  }

  async issueDocument(adminUserId: string, input: IssueDocumentInput) {
    const targetUser = this.db
      .select()
      .from(schema.user)
      .where(eq(schema.user.id, input.userId))
      .get();

    if (!targetUser) {
      throw new NotFoundException('User not found');
    }

    const issuedAt = new Date(`${input.data.issueDate}T00:00:00.000Z`);
    const expiresAt = new Date(`${input.data.expiryDate}T23:59:59.999Z`);

    const maxRetries = 10;
    let createdDoc: schema.IdentityDocument | null = null;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      const documentNumber = generateDocumentNumber();
      try {
        createdDoc = this.db
          .insert(schema.identityDocument)
          .values({
            id: randomUUID(),
            userId: input.userId,
            type: input.type,
            documentNumber,
            payload: input.data,
            status: 'issued',
            issuedBy: adminUserId,
            issuedAt,
            expiresAt,
            revokedAt: null,
          })
          .returning()
          .get();
        break;
      } catch (error: unknown) {
        const sqliteError = error as { code?: string };
        if (
          sqliteError.code === 'SQLITE_CONSTRAINT_UNIQUE' &&
          attempt < maxRetries - 1
        ) {
          continue;
        }
        throw error;
      }
    }

    if (!createdDoc) {
      throw new InternalServerErrorException(
        'Failed to generate unique document number',
      );
    }

    return {
      id: createdDoc.id,
      userId: createdDoc.userId,
      userEmail: targetUser.email,
      type: createdDoc.type,
      documentNumber: createdDoc.documentNumber,
      status: createdDoc.status,
      issuedAt: createdDoc.issuedAt,
      expiresAt: createdDoc.expiresAt,
      revokedAt: createdDoc.revokedAt,
    };
  }

  async revokeDocument(documentId: string) {
    const existing = this.db
      .select({
        doc: schema.identityDocument,
        userEmail: schema.user.email,
      })
      .from(schema.identityDocument)
      .innerJoin(
        schema.user,
        eq(schema.identityDocument.userId, schema.user.id),
      )
      .where(eq(schema.identityDocument.id, documentId))
      .get();

    if (!existing) {
      throw new NotFoundException('Document not found');
    }

    let doc = existing.doc;
    if (doc.status !== 'revoked') {
      const now = new Date();
      doc = this.db
        .update(schema.identityDocument)
        .set({
          status: 'revoked',
          revokedAt: now,
        })
        .where(eq(schema.identityDocument.id, documentId))
        .returning()
        .get();
    }

    return {
      id: doc.id,
      userId: doc.userId,
      userEmail: existing.userEmail,
      type: doc.type,
      documentNumber: doc.documentNumber,
      status: doc.status,
      issuedAt: doc.issuedAt,
      expiresAt: doc.expiresAt,
      revokedAt: doc.revokedAt,
    };
  }
}
