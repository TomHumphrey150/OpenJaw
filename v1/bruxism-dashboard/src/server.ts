import express from "express";
import cors from "cors";
import path from "path";
import fs from "fs";

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Serve static files from public directory
app.use(express.static(path.join(__dirname, "../public")));

// API Endpoints
app.get("/api/interventions", (req, res) => {
  try {
    const dataPath = path.join(__dirname, "../data/interventions.json");
    const data = JSON.parse(fs.readFileSync(dataPath, "utf-8"));
    res.json(data);
  } catch (error) {
    console.error("Error reading interventions.json:", error);
    res.status(500).json({ error: "Failed to load interventions data" });
  }
});

app.get("/api/bruxism-info", (req, res) => {
  try {
    const dataPath = path.join(__dirname, "../data/bruxism-info.json");
    const data = JSON.parse(fs.readFileSync(dataPath, "utf-8"));
    res.json(data);
  } catch (error) {
    console.error("Error reading bruxism-info.json:", error);
    res.status(500).json({ error: "Failed to load bruxism info data" });
  }
});

// Health check endpoint (for server detection)
app.get("/api/health", (req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// Fallback to index.html for SPA-like behavior
app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "../public/index.html"));
});

app.listen(PORT, () => {
  console.log(`
============================================
  Bruxism Dashboard
============================================
  Server running at http://localhost:${PORT}

  API Endpoints:
    GET /api/interventions  - All interventions
    GET /api/bruxism-info   - Bruxism information
    GET /api/health         - Server health check
============================================
  `);
});
