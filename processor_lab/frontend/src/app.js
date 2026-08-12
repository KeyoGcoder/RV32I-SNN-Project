const { useState, useEffect, useRef, useCallback } = React;

// ---- Config -----------------------------------------------------------
const API_BASE = "http://localhost:8000";
const RUN_ENDPOINT = `${API_BASE}/api/run`;
const BACKEND_POLL_MS = 8000;

const SAMPLE_PROGRAM = `// Sample bare-metal RV32I program
// Computes a small sum and returns it in a0 (x10)
int main() {
    int a = 5;
    int b = 3;
    int sum = a + b;
    return sum;
}
`;

// ---- Helpers ------------------------------------------------------------

// Turns a raw backend/network failure into a friendly, actionable message.
function classifyError({ networkError, httpStatus, data }) {
  // 1. Totally unreachable backend (fetch threw, e.g. TypeError: Failed to fetch)
  if (networkError) {
    return {
      title: "Backend unreachable",
      message: `Could not reach the lab backend at ${API_BASE}.`,
      hint: "Make sure the FastAPI server is running (uvicorn main:app --app-dir backend --reload) and that nothing is blocking port 8000.",
      kind: "offline",
    };
  }

  const errText = (data && (data.error || data.message)) || "";
  const status = (data && data.status) || "";
  const lower = `${status} ${errText}`.toLowerCase();

  // 2. Backend responded but with a non-2xx HTTP status and no useful body
  if (httpStatus && httpStatus >= 500 && !errText) {
    return {
      title: "Backend error",
      message: `The backend returned HTTP ${httpStatus} with no details.`,
      hint: "Check the backend terminal/log for a stack trace.",
      kind: "backend",
    };
  }

  // 3. C compilation failure
  if (
    lower.includes("compile") ||
    lower.includes("gcc") ||
    lower.includes("riscv-none-elf-gcc") ||
    /error:.*\.c/i.test(errText)
  ) {
    return {
      title: "Compilation failed",
      message: errText || "The C program failed to compile.",
      hint: "Check your source for syntax errors. Only rv32i/ilp32-compatible C is supported (no floating point, no standard library calls, no OS/syscalls).",
      kind: "compile",
    };
  }

  // 4. XSim not available / misconfigured on the backend
  if (
    lower.includes("rdi_datadir") ||
    lower.includes("xsim_unavailable") ||
    (lower.includes("xsim") &&
      (lower.includes("not found") ||
        lower.includes("not recognized") ||
        lower.includes("cannot find") ||
        lower.includes("no such file") ||
        lower.includes("unable to")))
  ) {
    return {
      title: "Simulator unavailable",
      message: "The XSim simulator could not be started on the backend.",
      hint: "This is a server/environment issue, not a problem with your code — Vivado XSim isn't reachable or isn't configured correctly on the machine running the backend.",
      kind: "xsim_unavailable",
    };
  }

  // 5. XSim timeout
  if (lower.includes("timed out") || lower.includes("timeout")) {
    return {
      title: "Simulation timed out",
      message: "XSim started but did not finish within the allotted time.",
      hint: "The simulator likely hung on the backend rather than your program being at fault. See XSIM_DEBUG_HANDOFF.md for known causes.",
      kind: "timeout",
    };
  }

  // 6. Generic simulation failure
  if (lower.includes("simulation") || status === "simulation_failed" || status === "failed") {
    return {
      title: "Simulation failed",
      message: errText || "The simulation did not complete successfully.",
      hint: "",
      kind: "simulation",
    };
  }

  // 7. Fallback
  return {
    title: "Run failed",
    message: errText || "The backend reported a failure without further details.",
    hint: "",
    kind: "unknown",
  };
}

// Attempts to pull an x10/a0 return value and PC out of whatever shape
// `simulation` happens to be (object or raw string), without assuming
// a strict backend contract.
function parseSimulation(simulation) {
  if (simulation === undefined || simulation === null) return null;

  const isObject = typeof simulation === "object";
  const raw = isObject ? JSON.stringify(simulation, null, 2) : String(simulation);
  const haystack = isObject ? JSON.stringify(simulation) : simulation;

  let x10 = null;
  let pc = null;

  if (isObject) {
    x10 =
      simulation.x10 ?? simulation.X10 ?? simulation.a0 ?? simulation.A0 ?? null;
    pc = simulation.pc ?? simulation.PC ?? null;
  }

  if (x10 === null) {
    const m = haystack.match(/x10\s*=\s*([0-9a-fx]+)/i) || haystack.match(/a0\s*=\s*([0-9a-fx]+)/i);
    if (m) x10 = m[1];
  }
  if (pc === null) {
    const m = haystack.match(/PC\s*=\s*([0-9a-fx]+)/i);
    if (m) pc = m[1];
  }

  return { x10, pc, raw };
}

function hexToDecimal(hex) {
  if (hex === null || hex === undefined) return null;
  const cleaned = String(hex).trim().replace(/^0x/i, "");
  if (!/^[0-9a-f]+$/i.test(cleaned)) return null;
  // Interpret as signed 32-bit, since a0 commonly carries a signed C return value.
  const unsigned = parseInt(cleaned, 16);
  if (Number.isNaN(unsigned)) return null;
  const signed = unsigned > 0x7fffffff ? unsigned - 0x100000000 : unsigned;
  return { unsigned, signed };
}

function machineCodeToText(machineCode) {
  if (machineCode === undefined || machineCode === null) return "";
  if (Array.isArray(machineCode)) return machineCode.join("\n");
  if (typeof machineCode === "object") return JSON.stringify(machineCode, null, 2);
  return String(machineCode);
}

// ---- Components -----------------------------------------------------------

function BackendStatusPill({ status, onRetry }) {
  const label =
    status === "online" ? "Backend online" : status === "offline" ? "Backend offline" : "Checking backend…";
  return (
    <div className="status-pill">
      <span className={`dot ${status}`} />
      <span>{label}</span>
      {status === "offline" && (
        <button className="retry-btn" onClick={onRetry}>
          Retry
        </button>
      )}
    </div>
  );
}

function ErrorBanner({ error }) {
  if (!error) return null;
  return (
    <div className="banner error">
      <div className="title">{error.title}</div>
      <div>{error.message}</div>
      {error.hint && <div className="hint">{error.hint}</div>}
    </div>
  );
}

function A0Panel({ sim }) {
  if (!sim || (sim.x10 === null && sim.pc === null)) return null;
  const dec = hexToDecimal(sim.x10);
  return (
    <div className="a0-panel">
      {sim.x10 !== null && (
        <div className="a0-metric">
          <div className="label">x10 / a0 (return value)</div>
          <div className="value">{sim.x10}</div>
          {dec && (
            <div className="value dec">
              = {dec.signed} (signed) / {dec.unsigned} (unsigned)
            </div>
          )}
        </div>
      )}
      {sim.pc !== null && (
        <div className="a0-metric">
          <div className="label">Final PC</div>
          <div className="value">{sim.pc}</div>
        </div>
      )}
    </div>
  );
}

function App() {
  const [code, setCode] = useState(SAMPLE_PROGRAM);
  const [backendStatus, setBackendStatus] = useState("checking"); // checking | online | offline
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState(null); // raw backend JSON
  const [uiError, setUiError] = useState(null);
  const pollRef = useRef(null);

  const checkBackend = useCallback(async () => {
    setBackendStatus((prev) => (prev === "offline" ? "checking" : prev === "online" ? prev : "checking"));
    try {
      // Any response (even 404) means the server is up. Only a network-level
      // failure (server not running / unreachable) throws here.
      await fetch(`${API_BASE}/api/health`, { method: "GET", cache: "no-store" });
      setBackendStatus("online");
    } catch (e) {
      setBackendStatus("offline");
    }
  }, []);

  useEffect(() => {
    checkBackend();
  }, [checkBackend]);

  // Poll while offline so the pill recovers on its own once the backend comes up.
  useEffect(() => {
    if (backendStatus === "offline") {
      pollRef.current = setInterval(checkBackend, BACKEND_POLL_MS);
    } else if (pollRef.current) {
      clearInterval(pollRef.current);
      pollRef.current = null;
    }
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, [backendStatus, checkBackend]);

  const handleRun = async () => {
    setRunning(true);
    setUiError(null);
    setResult(null);

    let response;
    try {
      response = await fetch(RUN_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ source: code }),
      });
    } catch (err) {
      // fetch() itself threw -> network-level failure (offline / CORS / DNS / etc.)
      setBackendStatus("offline");
      setUiError(classifyError({ networkError: true }));
      setRunning(false);
      return;
    }

    setBackendStatus("online");

    let data = null;
    try {
      data = await response.json();
    } catch (parseErr) {
      setUiError({
        title: "Invalid backend response",
        message: "The backend responded, but the body wasn't valid JSON.",
        hint: "Check the backend logs for an unhandled exception.",
      });
      setRunning(false);
      return;
    }

    setResult(data);

    const simulationFailed =
      data &&
      data.simulation &&
      ["failed", "not_run"].includes(String(data.simulation.status || "").toLowerCase());
    const failed =
      !response.ok ||
      (data && data.status && !["success", "ok", "completed"].includes(String(data.status).toLowerCase())) ||
      (data && data.error) ||
      simulationFailed;

    if (failed) {
      setUiError(classifyError({
        httpStatus: response.status,
        data: simulationFailed
          ? { ...data, status: data.simulation.status, message: data.simulation.message }
          : data,
      }));
    }

    setRunning(false);
  };

  const handleLoadSample = () => {
    setCode(SAMPLE_PROGRAM);
    setResult(null);
    setUiError(null);
  };

  const sim = result ? parseSimulation(result.simulation) : null;
  const compiledOk = result && !(result.error && !result.assembly);

  return (
    <React.Fragment>
      <header className="app-header">
        <h1>
          RV32I Processor Lab
          <span className="sub">Compile → simulate on the custom single-cycle RV32I core</span>
        </h1>
        <BackendStatusPill status={backendStatus} onRetry={checkBackend} />
      </header>

      {backendStatus === "offline" && (
        <div className="banner offline">
          <div className="title" style={{ color: "var(--red)" }}>
            Backend offline
          </div>
          <div>
            Can't reach {API_BASE}. Start the backend, then click Retry above, or press "Run on RV32I" to try
            again.
          </div>
        </div>
      )}

      <div className="layout">
        <div className="card">
          <h2>C Source</h2>
          <textarea
            className="code-editor"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            spellCheck="false"
          />
          <div className="btn-row">
            <button className="btn primary" onClick={handleRun} disabled={running}>
              {running ? "Running…" : "Run on RV32I"}
            </button>
            <button className="btn secondary" onClick={handleLoadSample} disabled={running}>
              Load sample program
            </button>
          </div>
        </div>

        <div className="card">
          <h2>Results</h2>

          <ErrorBanner error={uiError} />

          {!result && !uiError && <div className="placeholder">Run a program to see results here.</div>}

          {result && (
            <React.Fragment>
              <div className="result-section">
                <span className={`status-badge ${uiError ? "fail" : "ok"}`}>
                  {uiError ? "Failed" : "Success"}
                </span>
                {result.status && (
                  <span style={{ marginLeft: 10, color: "var(--muted)", fontSize: 12 }}>
                    backend status: {String(result.status)}
                  </span>
                )}
              </div>

              {sim && (sim.x10 !== null || sim.pc !== null) && (
                <div className="result-section">
                  <h2>Return value</h2>
                  <A0Panel sim={sim} />
                </div>
              )}

              {result.assembly && (
                <div className="result-section">
                  <h2>Assembly</h2>
                  <pre className="output">{result.assembly}</pre>
                </div>
              )}

              {result.machine_code && (
                <div className="result-section">
                  <h2>Machine code (program.mem)</h2>
                  <pre className="output">{machineCodeToText(result.machine_code)}</pre>
                </div>
              )}

              {result.simulation && (
                <div className="result-section">
                  <h2>Simulation output</h2>
                  <pre className="output">{sim ? sim.raw : String(result.simulation)}</pre>
                </div>
              )}
            </React.Fragment>
          )}
        </div>
      </div>

      <footer className="foot">API: {RUN_ENDPOINT}</footer>
    </React.Fragment>
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
