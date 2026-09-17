// Minimal service showing the integration contract:
//   - JSON logs on stdout (Alloy collects them; trace_id injected by OpenTelemetry)
//   - traces and metrics pushed over OTLP to Alloy (auto-instrumentation)
const express = require("express");
const pino = require("pino");
const { trace } = require("@opentelemetry/api");

const logger = pino({
  level: process.env.LOG_LEVEL || "info",
  // "info" instead of 30: Alloy turns it into the indexed `level` label.
  formatters: { level: (label) => ({ level: label }) },
});
const app = express();

app.get("/health", (_req, res) => res.json({ status: "ok" }));

app.get("/users", async (_req, res) => {
  const tracer = trace.getTracer("node-app-example");
  const users = await tracer.startActiveSpan("db.fetch-users", async (span) => {
    await new Promise((r) => setTimeout(r, 40));
    span.setAttribute("db.rows", 2);
    span.end();
    return [{ id: 1 }, { id: 2 }];
  });
  logger.info({ count: users.length }, "users served");
  res.json(users);
});

const port = Number(process.env.PORT || 3000);
app.listen(port, () => logger.info({ port }, "listening"));
