import subprocess
from fastapi import Request
def bad(request: Request):
    subprocess.run(request.query_params.get("cmd"), shell=True)
