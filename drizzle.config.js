import { defineConfig } from 'drizzle-kit';
import dotenv from 'dotenv';


dotenv.config();

export default defineConfig({
  schema: './shared/schema.ts',
  out: './drizzle',
  driver: 'pg',
  dbCredentials: {
    connectionString: process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/powerchat',
  },
  verbose: true,
  strict: true,
});
