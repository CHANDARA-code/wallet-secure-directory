import { BadRequestException } from '@nestjs/common';
import { randomInt } from 'node:crypto';
import { z } from 'zod';

function isValidCalendarDate(val: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(val)) {
    return false;
  }
  const [yearStr, monthStr, dayStr] = val.split('-');
  const year = Number(yearStr);
  const month = Number(monthStr);
  const day = Number(dayStr);
  if (
    year < 1900 ||
    year > 2100 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > 31
  ) {
    return false;
  }
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

const calendarDateSchema = z.string().refine(isValidCalendarDate, {
  message: 'Must be a valid calendar date in YYYY-MM-DD format',
});

export const drivingLicenseDataSchema = z
  .object({
    fullName: z.string().trim().min(1, 'fullName is required'),
    dateOfBirth: calendarDateSchema,
    address: z.string().trim().min(1, 'address is required'),
    nationality: z.string().trim().min(1, 'nationality is required'),
    issuingAuthority: z.string().trim().min(1, 'issuingAuthority is required'),
    licenseClasses: z
      .array(z.string().trim().min(1, 'licenseClass cannot be empty'))
      .min(1, 'At least one license class is required'),
    restrictions: z.array(z.string().trim().min(1)),
    issueDate: calendarDateSchema,
    expiryDate: calendarDateSchema,
  })
  .strict()
  .refine((data) => data.expiryDate > data.issueDate, {
    message: 'expiryDate must be after issueDate',
    path: ['expiryDate'],
  });

export type DrivingLicenseData = z.infer<typeof drivingLicenseDataSchema>;

export const issueDocumentSchema = z
  .object({
    userId: z.string().trim().min(1, 'userId is required'),
    type: z.literal('driving_license'),
    data: drivingLicenseDataSchema,
  })
  .strict();

export type IssueDocumentInput = z.infer<typeof issueDocumentSchema>;

export const adminUsersQuerySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(100).default(20),
    offset: z.coerce.number().int().min(0).default(0),
    q: z.string().optional(),
  })
  .strict();

export type AdminUsersQuery = z.infer<typeof adminUsersQuerySchema>;

export const adminDocumentsQuerySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(100).default(20),
    offset: z.coerce.number().int().min(0).default(0),
    userId: z.preprocess(
      (val) => (typeof val === 'string' && val.trim() === '' ? undefined : val),
      z.string().trim().min(1).optional(),
    ),
  })
  .strict();

export type AdminDocumentsQuery = z.infer<typeof adminDocumentsQuerySchema>;

export function generateDocumentNumber(): string {
  const digits = Array.from({ length: 10 }, () => randomInt(0, 10)).join('');
  return `DL-${digits}`;
}

export function parseOrThrowBadRequest<T>(
  schema: z.ZodType<T>,
  input: unknown,
): T {
  const result = schema.safeParse(input);
  if (!result.success) {
    const messages = result.error.issues.map((issue) => {
      const path = issue.path.join('.');
      return path.length > 0 ? `${path}: ${issue.message}` : issue.message;
    });
    throw new BadRequestException(messages);
  }
  return result.data;
}
