from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from lab_runner import run_program

app = FastAPI(title="RISC-V Processor Lab")
app.add_middleware(CORSMiddleware, allow_origins=["http://localhost:5173", "http://localhost:8000"], allow_methods=["*"], allow_headers=["*"])

class Program(BaseModel):
    source: str

@app.get("/api/health")
def health():
    return {"status": "ok"}

@app.post("/api/run")
def run(program: Program):
    return run_program(program.source)
