import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import { paths } from "../config";
import { runMigrations } from "./migrations";

fs.mkdirSync(path.dirname(paths.dbFile), { recursive: true });

export const db = new Database(paths.dbFile);
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");
db.pragma("busy_timeout = 5000");

runMigrations(db);
