import { eq } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { createAuth } from '../src/auth/auth.factory.js';
import { validateEnv } from '../src/config/env.js';
import { openSqlite } from '../src/database/database.module.js';
import * as schema from '../src/database/schema.js';

async function main() {
  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;
  const name = process.env.ADMIN_NAME ?? 'Admin';

  if (!email || !password) {
    console.error(
      'ADMIN_EMAIL and ADMIN_PASSWORD environment variables are required.',
    );
    process.exit(1);
  }

  const env = validateEnv(process.env);
  const sqlite = openSqlite(env.DATABASE_PATH);
  const db = drizzle(sqlite, { schema });
  const auth = createAuth(db, env);

  const existing = db
    .select()
    .from(schema.user)
    .where(eq(schema.user.email, email))
    .get();

  if (!existing) {
    await auth.api.signUpEmail({
      body: {
        email,
        password,
        name,
      },
    });
  }

  db.update(schema.user)
    .set({ role: 'admin' })
    .where(eq(schema.user.email, email))
    .run();

  sqlite.close();
  console.log(`Admin user configured: ${email}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
