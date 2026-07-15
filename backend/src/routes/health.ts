import { Router } from "express";
import { db } from "../db";

export const healthRouter = Router();

healthRouter.get("/health", (_req, res) => {
  try {
    db.prepare("SELECT 1").get();
    res.json({ status: "ok" });
  } catch (err) {
    res.status(500).json({ status: "error" });
  }
});
