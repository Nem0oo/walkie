import fs from "node:fs";
import path from "node:path";
import type Database from "better-sqlite3";

export function runMigrations(db: Database.Database): void {
  db.exec(`CREATE TABLE IF NOT EXISTS _migrations (name TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')))`);

  const migrationsDir = path.join(__dirname, "migrations");
  const applied = new Set(
    db.prepare<[], { name: string }>("SELECT name FROM _migrations").all().map((row) => row.name)
  );

  const files = fs
    .readdirSync(migrationsDir)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = fs.readFileSync(path.join(migrationsDir, file), "utf8");
    const apply = db.transaction(() => {
      db.exec(sql);
      db.prepare("INSERT INTO _migrations (name) VALUES (?)").run(file);
    });
    apply();
    console.log(`Applied migration ${file}`);
  }
}
