#!/usr/bin/env tsx

/**
 * Script to run database migrations for unread message tracking
 */

import { pool } from './server/db';
import fs from 'fs';
import path from 'path';

async function runUnreadMessageMigration() {
  const client = await pool.connect();
  
  try {

    

    const migrationPath = path.join(process.cwd(), 'migrations', '003-add-unread-message-tracking.sql');
    
    if (!fs.existsSync(migrationPath)) {
      console.error('❌ Migration file not found:', migrationPath);
      process.exit(1);
    }
    
    const migrationSQL = fs.readFileSync(migrationPath, 'utf8');
    

    await client.query('BEGIN');
    

    

    await client.query(migrationSQL);
    

    await client.query('COMMIT');
    

    


    

    const columnsResult = await client.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'messages' AND column_name IN ('read_at')
      UNION
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'conversations' AND column_name IN ('unread_count')
    `);
    

    columnsResult.rows.forEach(row => {

    });
    

    const indexesResult = await client.query(`
      SELECT indexname 
      FROM pg_indexes 
      WHERE tablename IN ('messages', 'conversations') 
      AND indexname LIKE '%unread%' OR indexname LIKE '%read_at%'
    `);
    

    indexesResult.rows.forEach(row => {

    });
    

    const functionsResult = await client.query(`
      SELECT proname 
      FROM pg_proc 
      WHERE proname IN ('calculate_unread_count', 'update_conversation_unread_count', 'trigger_update_unread_count')
    `);
    

    functionsResult.rows.forEach(row => {

    });
    

    const triggersResult = await client.query(`
      SELECT trigger_name 
      FROM information_schema.triggers 
      WHERE trigger_name = 'trigger_messages_unread_count'
    `);
    

    triggersResult.rows.forEach(row => {

    });
    

    
  } catch (error) {

    await client.query('ROLLBACK');
    console.error('❌ Migration failed:', error);
    process.exit(1);
  } finally {
    client.release();
  }
}


if (require.main === module) {
  runUnreadMessageMigration().then(() => {

    process.exit(0);
  }).catch((error) => {
    console.error('❌ Migration script failed:', error);
    process.exit(1);
  });
}

export { runUnreadMessageMigration };
