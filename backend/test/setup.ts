// Imported first by every test file: config is read once at import time, so the
// environment must be in place before anything from src/ loads. Each test file runs
// in its own process (node --test), so each gets its own data directory and database.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), "walkie-test-"));
process.env.MAX_DURATION_SECONDS = "3";
process.env.TRUST_PROXY = "1";
process.env.PUBLIC_BASE_URL = "http://walkie.test";
